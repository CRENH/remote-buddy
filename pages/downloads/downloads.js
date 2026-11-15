(function () {
  var english = document.documentElement.lang === 'en';
  var tagBadge = document.getElementById('release-tag');
  var statusNote = document.getElementById('mirror-status');
  var githubLink = document.getElementById('github-release-link');
  var cardsContainer = document.getElementById('mirror-cards');
  var fallbackPanel = document.getElementById('mirror-fallback');

  if (!cardsContainer) return;

  function formatBytes(bytes) {
    if (!bytes || typeof bytes !== 'number') return '';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function detectPreferredArch() {
    var ua = (navigator.userAgent || '').toLowerCase();
    if (ua.indexOf('arm') !== -1 || ua.indexOf('apple') !== -1) return 'arm64';
    return null;
  }

  function renderPackages(manifest) {
    var tag = manifest && manifest.tag;
    var packages = manifest && manifest.packages;
    if (!tag || !packages || !packages.arm64 || !packages.intel) {
      throw new Error('Incomplete download manifest');
    }

    if (tagBadge) {
      tagBadge.textContent = (english ? 'Latest version: ' : '最新版本：') + tag;
      tagBadge.hidden = false;
    }
    if (githubLink && manifest.releasesUrl) {
      githubLink.href = manifest.releasesUrl;
    }

    var preferred = detectPreferredArch();
    var specs = [
      {
        key: 'arm64',
        title: english ? 'Mac with Apple Silicon' : 'Apple Silicon 芯片 Mac',
        subtitle: english
          ? 'For M1 / M2 / M3 / M4 and newer Apple Silicon Macs. Includes the app and virtual microphone driver.'
          : '适用于 M1 / M2 / M3 / M4 及更新款芯片 Mac，包含应用与虚拟麦克风驱动。',
        archLabel: 'arm64 · .pkg',
        recommended: preferred === 'arm64'
      },
      {
        key: 'intel',
        title: english ? 'Mac with Intel Processor' : 'Intel 处理器 Mac',
        subtitle: english
          ? 'For Intel-based Macs running macOS 14 or later. Includes the app and virtual microphone driver.'
          : '适用于运行 macOS 14 及以上的 Intel 芯片 Mac，包含应用与虚拟麦克风驱动。',
        archLabel: 'x86_64 · .pkg',
        recommended: preferred === 'intel'
      }
    ];

    if (packages.uninstaller && packages.uninstaller.name) {
      specs.push({
        key: 'uninstaller',
        title: english ? 'Universal Uninstaller' : '通用卸载安装包',
        subtitle: english
          ? 'Removes the app, virtual microphone driver, and optionally preferences/logs on Apple Silicon & Intel.'
          : '一键移除 App、虚拟麦克风驱动，并可选择清理设置与日志（Apple Silicon / Intel 通用）。',
        archLabel: 'universal · .pkg',
        recommended: false
      });
    }

    cardsContainer.innerHTML = '';
    specs.forEach(function (spec) {
      var pkg = packages[spec.key];
      if (!pkg || !pkg.name) return;

      var card = document.createElement('article');
      card.className = 'download-card' + (spec.recommended ? ' is-recommended' : '');

      var badgeHtml = spec.recommended
        ? '<span class="download-badge">' + (english ? 'Recommended' : '当前设备推荐') + '</span>'
        : '';
      var sizeText = formatBytes(pkg.size);

      card.innerHTML =
        '<h2>' + spec.title + badgeHtml + '</h2>' +
        '<p>' + spec.subtitle + '</p>' +
        '<div class="download-meta">' +
          '<span><code>' + pkg.name + '</code></span>' +
          (sizeText ? '<span>' + sizeText + '</span>' : '') +
          '<span>' + spec.archLabel + '</span>' +
        '</div>' +
        '<div class="download-actions">' +
          '<a class="button primary" href="' + encodeURIComponent(pkg.name) + '" download>' +
            (english ? 'Download from Website ↓' : '从官网直接下载 ↓') +
          '</a>' +
          '<a class="button secondary" href="https://github.com/zfdang/remote-buddy/releases/download/' +
            encodeURIComponent(tag) + '/' + encodeURIComponent(pkg.name) + '">' +
            (english ? 'GitHub Mirror ↗' : 'GitHub Releases 备选 ↗') +
          '</a>' +
        '</div>';

      cardsContainer.appendChild(card);
    });

    if (fallbackPanel) fallbackPanel.hidden = true;
    if (statusNote) {
      statusNote.textContent = english
        ? 'If direct download from remote.zfdang.com is slow or unavailable, use the GitHub Releases mirror button.'
        : '所有安装包均使用相同的签名产物：默认优先从官网镜像（remote.zfdang.com）下载，也可随时使用 GitHub Releases 备选通道。';
    }
  }

  fetch('latest.json', { cache: 'no-store' })
    .then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.json();
    })
    .then(renderPackages)
    .catch(function () {
      if (fallbackPanel) fallbackPanel.hidden = false;
      if (statusNote) {
        statusNote.textContent = english
          ? 'Direct website mirror index is unavailable in this environment; please use GitHub Releases below.'
          : '当前预览环境尚未同步官网安装包清单，请直接通过下方 GitHub Releases 下载最新安装包。';
      }
    });
})();
