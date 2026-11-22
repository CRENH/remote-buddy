#!/usr/bin/env python3
"""Back up and restore only the remote key mappings of Remote Buddy (upstream or CRENH build).

backup:  writes each remote's mappings plus the custom application list to a JSON file.
restore: dry run by default; --apply writes the mappings back into the matching local remotes,
         leaving pairing data, gain and every other setting untouched. Quit the app first.
"""
import argparse
import copy
import datetime
import json
import plistlib
import subprocess
import sys
from pathlib import Path

DOMAIN = 'com.zfdang.remote-buddy'
EXECUTABLE = 'RemoteBuddy'
FORMAT = 'remote-buddy-mappings'
VERSION = 1
PROFILES_KEY = 'remoteDeviceProfiles'
APPS_KEY = 'customApplicationProfiles'
MAPPING_FIELDS = ('buttonBindings', 'buttonShortcuts', 'buttonApplicationProfileIDs', 'secondaryButtonBindings')
DEFAULT_DIR = Path.home() / 'RemoteBuddy-Backup'


def timestamp():
    return datetime.datetime.now().strftime('%Y%m%d-%H%M%S')


def read_domain(domain):
    result = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True, check=True)
    return plistlib.loads(result.stdout)


def decode_list(domain_values, key):
    data = domain_values.get(key)
    return json.loads(data) if data else []


def make_backup(domain_values, now):
    profiles = decode_list(domain_values, PROFILES_KEY)
    if not profiles:
        raise ValueError('设置里没有遥控器档案，没有可备份的映射。')
    return {
        'format': FORMAT,
        'version': VERSION,
        'exportedAt': now,
        'remotes': [
            {'id': p['id'], 'model': p['model'], 'name': p.get('customName', ''), 'mappings': p['mappings']}
            for p in profiles
        ],
        'customApplications': decode_list(domain_values, APPS_KEY),
    }


def match_remote(profile, remotes):
    """Same profile ID first (same Mac), then same model with the same name, then the first of that model."""
    for remote in remotes:
        if remote['id'] == profile['id']:
            return remote, '同一个档案'
    same_model = [r for r in remotes if r['model'] == profile['model']]
    for remote in same_model:
        if remote['name'] == profile.get('customName', ''):
            return remote, '型号和名称相同'
    if same_model:
        return same_model[0], '型号相同'
    return None, None


def merge_applications(local_apps, backup_apps):
    """Returns the merged app list, a backup-ID to local-ID map, and the names of added apps."""
    merged = copy.deepcopy(local_apps)
    by_id = {a['id']: a for a in merged}
    by_bundle = {a.get('bundleIdentifier'): a for a in merged}
    id_map, added = {}, []
    for app in backup_apps:
        if app['id'] in by_id:
            id_map[app['id']] = app['id']
        elif app.get('bundleIdentifier') in by_bundle:
            id_map[app['id']] = by_bundle[app['bundleIdentifier']]['id']
        else:
            merged.append(copy.deepcopy(app))
            by_id[app['id']] = app
            id_map[app['id']] = app['id']
            added.append(app.get('displayName') or app.get('bundleIdentifier') or app['id'])
    return merged, id_map, added


def remap_references(mappings, id_map, known_ids):
    """Points application references at local IDs; returns the references that resolve nowhere."""
    unresolved = []
    references = mappings.get('buttonApplicationProfileIDs') or {}
    for button, app_id in references.items():
        references[button] = id_map.get(app_id, app_id)
        if references[button] not in known_ids:
            unresolved.append(button)
    for button, triggers in (mappings.get('secondaryButtonBindings') or {}).items():
        for trigger, configured in triggers.items():
            app_id = configured.get('applicationProfileID')
            if app_id is None:
                continue
            configured['applicationProfileID'] = id_map.get(app_id, app_id)
            if configured['applicationProfileID'] not in known_ids:
                unresolved.append(f'{button}/{trigger}')
    return unresolved


def changed_keys(old, new):
    changed = set()
    for field in MAPPING_FIELDS:
        before, after = old.get(field) or {}, new.get(field) or {}
        changed.update(k for k in set(before) | set(after) if before.get(k) != after.get(k))
    return sorted(changed)


def plan_restore(domain_values, backup):
    if backup.get('format') != FORMAT:
        raise ValueError('这不是本脚本导出的映射备份文件。')
    profiles = decode_list(domain_values, PROFILES_KEY)
    if not profiles:
        raise ValueError('设置里没有遥控器档案：先在 App 里完成配对，再恢复映射。')
    apps, id_map, added_apps = merge_applications(decode_list(domain_values, APPS_KEY), backup.get('customApplications', []))
    known_ids = {a['id'] for a in apps}
    lines, used = [], set()
    changed_total = 0
    for profile in profiles:
        label = f"{profile.get('customName') or '(未命名)'}（{profile['model']}）"
        remote, how = match_remote(profile, backup['remotes'])
        if remote is None:
            lines.append(f'- {label}：备份里没有这个型号，保持不变')
            continue
        used.add(id(remote))
        mappings = copy.deepcopy(remote['mappings'])
        unresolved = remap_references(mappings, id_map, known_ids)
        changed = changed_keys(profile['mappings'], mappings)
        changed_total += len(changed)
        profile['mappings'] = mappings
        detail = '、'.join(changed) if changed else '无'
        lines.append(f"- {label}：对应备份里的「{remote['name'] or '(未命名)'}」（{how}），有变化的键：{detail}")
        if unresolved:
            lines.append(f"  注意：这些键引用的 App 找不到，恢复后不会生效：{'、'.join(unresolved)}")
    for remote in backup['remotes']:
        if id(remote) not in used:
            lines.append(f"- 备份里的「{remote['name'] or '(未命名)'}」（{remote['model']}）：本机没有对应的遥控器，跳过")
    if added_apps:
        lines.append(f"- 新增自定义 App：{'、'.join(added_apps)}")
    return profiles, apps, lines, changed_total


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()


def write_list(domain, key, value):
    subprocess.run(['defaults', 'write', domain, key, '-data', encode(value).hex()], check=True)


def app_is_running():
    return subprocess.run(['pgrep', '-x', EXECUTABLE], capture_output=True).returncode == 0


def command_backup(args):
    output = args.output or DEFAULT_DIR / f'mappings-{timestamp()}.json'
    backup = make_backup(read_domain(args.domain), datetime.datetime.now().isoformat(timespec='seconds'))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(backup, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"结论：已备份 {len(backup['remotes'])} 个遥控器的映射、{len(backup['customApplications'])} 个自定义 App → {output}")


def command_restore(args):
    backup = json.loads(args.file.read_text(encoding='utf-8'))
    domain_values = read_domain(args.domain)
    profiles, apps, lines, changed_total = plan_restore(domain_values, backup)
    print('\n'.join(lines))
    if not args.apply:
        print(f'结论：试运行，什么都没改。共 {changed_total} 个键会变化；确认无误后退出 Remote Buddy，加 --apply 再运行一次。')
        return
    if app_is_running():
        sys.exit('结论：Remote Buddy 还在运行，没有写入。先从菜单栏图标点「退出」，再运行一次。')
    safety = args.safety_dir / f'before-restore-{timestamp()}.plist'
    safety.parent.mkdir(parents=True, exist_ok=True)
    safety.write_bytes(plistlib.dumps(domain_values))
    write_list(args.domain, APPS_KEY, apps)
    write_list(args.domain, PROFILES_KEY, profiles)
    print(f'结论：已写回映射，共 {changed_total} 个键变化，其他设置没动。打开 Remote Buddy 检查。')
    print(f'恢复前的完整设置已存到 {safety}；要撤销，退出 App 后运行：')
    print(f'defaults import {args.domain} "{safety}"')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--domain', default=DOMAIN, help=argparse.SUPPRESS)
    commands = parser.add_subparsers(dest='command', required=True)
    backup = commands.add_parser('backup', help='备份映射')
    backup.add_argument('--output', type=Path, help=f'备份文件路径（默认 {DEFAULT_DIR}/mappings-<时间>.json）')
    backup.set_defaults(run=command_backup)
    restore = commands.add_parser('restore', help='恢复映射（默认试运行）')
    restore.add_argument('file', type=Path, help='backup 生成的 JSON 文件')
    restore.add_argument('--apply', action='store_true', help='真正写入（需先退出 App）')
    restore.add_argument('--safety-dir', type=Path, default=DEFAULT_DIR, help=argparse.SUPPRESS)
    restore.set_defaults(run=command_restore)
    args = parser.parse_args()
    try:
        args.run(args)
    except (ValueError, KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        sys.exit(f'结论：失败，没有写入。原因：{error}')


if __name__ == '__main__':
    main()
