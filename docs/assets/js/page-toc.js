(function () {
    'use strict';

    function IsRightTocEnabled() {
        var meta = document.querySelector('meta[name="ffu-right-toc"]');
        if (meta && meta.content && meta.content.toLowerCase() === 'false') {
            return false;
        }

        return true;
    }

    function IsDesktopViewport() {
        try {
            return window.matchMedia && window.matchMedia('(min-width: 66.5rem)').matches;
        } catch (e) {
            return false;
        }
    }

    function GetHeadings(container) {
        var headings = container.querySelectorAll('h2, h3');
        var results = [];

        for (var i = 0; i < headings.length; i++) {
            var heading = headings[i];

            if (heading.classList.contains('no_toc')) {
                continue;
            }

            var id = heading.getAttribute('id');
            if (!id) {
                continue;
            }

            var text = (heading.textContent || '').trim();
            if (!text) {
                continue;
            }

            results.push({
                level: heading.tagName.toLowerCase(),
                id: id,
                text: text
            });
        }

        return results;
    }

    function BuildToc(headings) {
        var nav = document.createElement('nav');
        nav.className = 'page-toc';
        nav.setAttribute('aria-label', 'On this page');

        var title = document.createElement('div');
        title.className = 'page-toc__title';
        title.textContent = 'In this article';
        nav.appendChild(title);

        var list = document.createElement('ul');
        list.className = 'page-toc__list';

        for (var i = 0; i < headings.length; i++) {
            var item = headings[i];

            var li = document.createElement('li');
            li.className = 'page-toc__item page-toc__item--' + item.level;

            var a = document.createElement('a');
            a.className = 'page-toc__link';
            a.href = '#' + item.id;
            a.textContent = item.text;

            li.appendChild(a);
            list.appendChild(li);
        }

        nav.appendChild(list);
        return nav;
    }

    function SetActiveTocLink(toc, activeId) {
        if (!toc) {
            return;
        }

        var links = toc.querySelectorAll('.page-toc__link');
        for (var i = 0; i < links.length; i++) {
            var link = links[i];
            var href = link.getAttribute('href') || '';
            var isActive = ('#' + activeId) === href;

            if (isActive) {
                link.classList.add('is-active');

                /* Keep the active item visible inside the TOC panel */
                try {
                    link.scrollIntoView({ block: 'nearest' });
                } catch (e) {
                    link.scrollIntoView();
                }
            } else {
                link.classList.remove('is-active');
            }
        }
    }

    function SetupScrollSpy(main, toc, headings) {
        if (!main || !toc || !headings || headings.length < 1) {
            return;
        }

        /* Scrollspy is desktop-only; on mobile it can cause "fighting" scroll behavior */
        if (!IsDesktopViewport()) {
            return;
        }

        var headingElements = [];
        for (var i = 0; i < headings.length; i++) {
            var el = document.getElementById(headings[i].id);
            if (el) {
                headingElements.push(el);
            }
        }

        if (headingElements.length < 1) {
            return;
        }

        var activeId = null;
        var ticking = false;
        var lockActiveUntilMs = 0;

        function IsNearBottomOfPage() {
            var thresholdPx = 24;
            var scrollY = window.scrollY || window.pageYOffset || 0;
            var viewportBottom = scrollY + window.innerHeight;
            var pageHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);

            return viewportBottom >= (pageHeight - thresholdPx);
        }

        function GetCurrentHeadingId() {
            /* If we're at the bottom, force the last heading active (Learn-like behavior) */
            if (IsNearBottomOfPage()) {
                return headingElements[headingElements.length - 1].getAttribute('id');
            }

            /* Choose the heading closest to the top "activation line" */
            var activationLine = 16;
            var current = null;

            for (var i = 0; i < headingElements.length; i++) {
                var rectTop = headingElements[i].getBoundingClientRect().top;

                if (rectTop <= activationLine) {
                    current = headingElements[i];
                    continue;
                }

                if (null === current) {
                    current = headingElements[i];
                }

                break;
            }

            if (null === current) {
                current = headingElements[0];
            }

            return current.getAttribute('id');
        }

        function Update() {
            ticking = false;

            if (Date.now() < lockActiveUntilMs) {
                return;
            }

            var currentId = GetCurrentHeadingId();
            if (!currentId || currentId === activeId) {
                return;
            }

            activeId = currentId;
            SetActiveTocLink(toc, activeId);
        }

        function OnScrollOrResize() {
            if (ticking) {
                return;
            }

            ticking = true;
            window.requestAnimationFrame(Update);
        }

        window.addEventListener('scroll', OnScrollOrResize, { passive: true });
        window.addEventListener('resize', OnScrollOrResize);

        /* Update immediately and also when clicking TOC links */
        toc.addEventListener('click', function (evt) {
            var target = evt.target;
            if (!target || !target.classList || !target.classList.contains('page-toc__link')) {
                return;
            }

            var href = target.getAttribute('href') || '';
            if (href.charAt(0) !== '#') {
                return;
            }

            var id = href.substring(1);
            if (!id) {
                return;
            }

            /* Prevent scrollspy from immediately overriding the clicked section */
            lockActiveUntilMs = Date.now() + 800;

            activeId = id;
            SetActiveTocLink(toc, activeId);
        });

        Update();
    }

    function InitRightToc() {
        if (!IsRightTocEnabled()) {
            return;
        }

        /* Desktop-only TOC: on mobile it interferes with scrolling */
        if (!IsDesktopViewport()) {
            var existingWrap = document.querySelector('.main-content-wrap');
            if (existingWrap) {
                var existingToc = existingWrap.querySelector('.page-toc');
                if (existingToc) {
                    existingToc.remove();
                }

                existingWrap.classList.remove('has-page-toc');
            }

            return;
        }

        var main = document.querySelector('.main-content main');
        if (!main) {
            return;
        }

        var headings = GetHeadings(main);
        if (headings.length < 2) {
            return;
        }

        var wrap = document.querySelector('.main-content-wrap');
        var content = document.querySelector('.main-content');
        if (!wrap || !content) {
            return;
        }

        if (wrap.querySelector('.page-toc')) {
            return;
        }

        wrap.classList.add('has-page-toc');

        var toc = BuildToc(headings);
        wrap.appendChild(toc);

        SetupScrollSpy(main, toc, headings);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', InitRightToc);
        return;
    }

    InitRightToc();
})();