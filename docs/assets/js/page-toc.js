(function () {
    'use strict';

    var scrollSpyDispose = null;
    var resizeReinitTimerId = null;
    var inlineMaxVisibleItems = 4;

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

    function RemoveExistingToc() {
        if (scrollSpyDispose) {
            scrollSpyDispose();
            scrollSpyDispose = null;
        }

        var existingTocs = document.querySelectorAll('.page-toc');
        for (var i = 0; i < existingTocs.length; i++) {
            existingTocs[i].remove();
        }

        var wrap = document.querySelector('.main-content-wrap');
        if (wrap) {
            wrap.classList.remove('has-page-toc');
        }
    }

    function InsertInlineToc(main, toc) {
        if (!main || !toc) {
            return;
        }

        var title = main.querySelector('h1');
        if (title && title.parentNode === main) {
            if (title.nextSibling) {
                main.insertBefore(toc, title.nextSibling);
                return;
            }

            main.appendChild(toc);
            return;
        }

        if (main.firstChild) {
            main.insertBefore(toc, main.firstChild);
            return;
        }

        main.appendChild(toc);
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

    function BuildToc(headings, options) {
        var variant = (options && options.variant) ? options.variant : 'right';
        var maxVisible = (options && options.maxVisible) ? options.maxVisible : 0;
        var isInline = 'inline' === variant;

        var nav = document.createElement('nav');
        nav.className = 'page-toc' + (isInline ? ' page-toc--inline' : '');
        nav.setAttribute('aria-label', 'On this page');

        var title = document.createElement('div');
        title.className = 'page-toc__title';
        title.textContent = 'In this article';
        nav.appendChild(title);

        var list = document.createElement('ul');
        list.className = 'page-toc__list';
        list.id = 'page-toc-list';

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

            if (isInline && maxVisible > 0 && i >= maxVisible) {
                li.classList.add('is-hidden');
            }
        }

        nav.appendChild(list);

        if (isInline && maxVisible > 0 && headings.length > maxVisible) {
            var hiddenCount = headings.length - maxVisible;
            var isExpanded = false;

            var toggle = document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'page-toc__toggle';
            toggle.setAttribute('aria-controls', list.id);
            toggle.setAttribute('aria-expanded', 'false');

            function SetToggleText() {
                if (isExpanded) {
                    toggle.textContent = 'Show less';
                } else {
                    toggle.textContent = 'Show ' + hiddenCount + ' more';
                }
            }

            function SetHiddenState() {
                var items = list.querySelectorAll('.page-toc__item');
                for (var j = 0; j < items.length; j++) {
                    if (j >= maxVisible) {
                        if (isExpanded) {
                            items[j].classList.remove('is-hidden');
                        } else {
                            items[j].classList.add('is-hidden');
                        }
                    }
                }

                toggle.setAttribute('aria-expanded', isExpanded ? 'true' : 'false');
                SetToggleText();
            }

            toggle.addEventListener('click', function () {
                isExpanded = !isExpanded;
                SetHiddenState();
            });

            SetHiddenState();
            nav.appendChild(toggle);
        }

        return nav;
    }

    function SetActiveTocLink(toc, activeId, keepVisibleInPanel) {
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

                if (keepVisibleInPanel) {
                    /* Keep the active item visible inside the TOC panel (desktop/right TOC only) */
                    try {
                        link.scrollIntoView({ block: 'nearest' });
                    } catch (e) {
                        link.scrollIntoView();
                    }
                }
            } else {
                link.classList.remove('is-active');
            }
        }
    }

    function SetupScrollSpy(main, toc, headings) {
        if (!main || !toc || !headings || headings.length < 1) {
            return null;
        }

        /* Scrollspy is desktop-only */
        if (!IsDesktopViewport()) {
            return null;
        }

        var headingElements = [];
        for (var i = 0; i < headings.length; i++) {
            var el = document.getElementById(headings[i].id);
            if (el) {
                headingElements.push(el);
            }
        }

        if (headingElements.length < 1) {
            return null;
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
            /* If we're at the bottom, force the last heading active */
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

            /* If the viewport becomes narrow after load, avoid scroll fighting */
            if (!IsDesktopViewport()) {
                return;
            }

            if (Date.now() < lockActiveUntilMs) {
                return;
            }

            var currentId = GetCurrentHeadingId();
            if (!currentId || currentId === activeId) {
                return;
            }

            activeId = currentId;
            SetActiveTocLink(toc, activeId, true);
        }

        function OnScrollOrResize() {
            if (ticking) {
                return;
            }

            ticking = true;
            window.requestAnimationFrame(Update);
        }

        function OnTocClick(evt) {
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
            SetActiveTocLink(toc, activeId, true);
        }

        window.addEventListener('scroll', OnScrollOrResize, { passive: true });
        window.addEventListener('resize', OnScrollOrResize);
        toc.addEventListener('click', OnTocClick);

        Update();

        return function DisposeScrollSpy() {
            window.removeEventListener('scroll', OnScrollOrResize);
            window.removeEventListener('resize', OnScrollOrResize);
            toc.removeEventListener('click', OnTocClick);
        };
    }

    function InitRightToc() {
        if (!IsRightTocEnabled()) {
            RemoveExistingToc();
            return;
        }

        var main = document.querySelector('.main-content main');
        if (!main) {
            return;
        }

        var headings = GetHeadings(main);
        if (headings.length < 2) {
            RemoveExistingToc();
            return;
        }

        if (IsDesktopViewport()) {
            RemoveExistingToc();

            var wrap = document.querySelector('.main-content-wrap');
            if (!wrap) {
                return;
            }

            wrap.classList.add('has-page-toc');

            var toc = BuildToc(headings, { variant: 'right' });
            wrap.appendChild(toc);

            scrollSpyDispose = SetupScrollSpy(main, toc, headings);
            return;
        }

        /* Narrow viewports: place TOC at the top of the article (Learn-like) */
        RemoveExistingToc();

        var inlineToc = BuildToc(headings, { variant: 'inline', maxVisible: inlineMaxVisibleItems });
        InsertInlineToc(main, inlineToc);
    }

    function OnViewportResize() {
        if (null !== resizeReinitTimerId) {
            window.clearTimeout(resizeReinitTimerId);
        }

        resizeReinitTimerId = window.setTimeout(InitRightToc, 150);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
            InitRightToc();
            window.addEventListener('resize', OnViewportResize);
        });

        return;
    }

    InitRightToc();
    window.addEventListener('resize', OnViewportResize);
})();