(function () {
    'use strict';

    function InitImageZoom() {
        if (window.mediumZoom === undefined) {
            return;
        }

        window.mediumZoom('.main-content img:not(.no-zoom):not([src$=".svg"])', {
            margin: 24,
            background: 'rgba(0,0,0,0.80)',
            scrollOffset: 0
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', InitImageZoom);
        return;
    }

    InitImageZoom();
})();