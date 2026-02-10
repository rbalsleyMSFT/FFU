(function () {
    'use strict';

    function HasToken(tokens, token) {
        for (var i = 0; i < tokens.length; i++) {
            if (tokens[i] === token) {
                return true;
            }
        }

        return false;
    }

    function AddRelToken(anchor, token) {
        var rel = (anchor.getAttribute('rel') || '').trim();
        var tokens = rel ? rel.split(/\s+/) : [];

        if (!HasToken(tokens, token)) {
            tokens.push(token);
        }

        anchor.setAttribute('rel', tokens.join(' ').trim());
    }

    function IsExternalHttpLink(url) {
        if (!url) {
            return false;
        }

        if (url.protocol !== 'http:' && url.protocol !== 'https:') {
            return false;
        }

        return url.origin !== window.location.origin;
    }

    function InitExternalLinksNewTab() {
        var mainContent = document.querySelector('.main-content');
        if (!mainContent) {
            return;
        }

        var anchors = mainContent.querySelectorAll('a[href]');
        for (var i = 0; i < anchors.length; i++) {
            var anchor = anchors[i];
            var href = (anchor.getAttribute('href') || '').trim();

            if (!href) {
                continue;
            }

            if (href.charAt(0) === '#') {
                continue;
            }

            if (href.indexOf('mailto:') === 0 || href.indexOf('tel:') === 0 || href.indexOf('javascript:') === 0) {
                continue;
            }

            var url = null;
            try {
                url = new URL(href, window.location.href);
            } catch (e) {
                continue;
            }

            if (!IsExternalHttpLink(url)) {
                continue;
            }

            var target = (anchor.getAttribute('target') || '').trim();

            if (!target) {
                anchor.setAttribute('target', '_blank');
                target = '_blank';
            }

            if (target === '_blank') {
                AddRelToken(anchor, 'noopener');
                AddRelToken(anchor, 'noreferrer');
            }
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', InitExternalLinksNewTab);
        return;
    }

    InitExternalLinksNewTab();
})();