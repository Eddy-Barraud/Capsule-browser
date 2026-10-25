// ruleset cosmetic: easyprivacy
(function uBOL_cosmeticSpecific_easyprivacy() {
    'use strict';
    const data = {"rulesetId":"easyprivacy","selectors":["{\"selector\":\"html[class^=\\\"loading\\\"]\",\"action\":[\"style\",\"visibility: visible !important;\"],\"cssable\":true}","{\"selector\":\".inviewSection:not(.is-show)\",\"action\":[\"style\",\"transform: translateY(0) !important; opacity: 1 !important;\"],\"cssable\":true}","{\"selector\":\"body[style=\\\"opacity: 0;\\\"]\",\"action\":[\"style\",\"opacity: 1 !important;\"],\"cssable\":true}"],"selectorLists":["0","1","2"],"selectorListRefs":[0,1,2,2],"hostnames":["anikore.jp","e-begin.jp","bitdefender.com","mustar.meitetsu.co.jp"],"hasEntities":false,"regexes":[]};

    const binarySearch = (haystack, needle, r) => {
        let l = 0, i = 0, d = 0, candidate;
        r = r >= 0 ? r : haystack.length;
        while ( l < r ) {
            i = l + r >>> 1;
            candidate = haystack[i];
            d = needle.length - candidate.length;
            if ( d === 0 ) {
                if ( needle === candidate ) { return i; }
                d = needle < candidate ? -1 : 1;
            }
            if ( d < 0 ) {
                r = i;
            } else {
                l = i + 1;
            }
        }
        return ~i;
    };

    const docloc = document.location;
    if ( !docloc ) { return; }
    const origins = [ docloc.origin ];
    if ( docloc.ancestorOrigins ) {
        origins.push(...docloc.ancestorOrigins);
    }
    const entries = origins.map((origin, i) => {
        const beg = origin.indexOf('://');
        if ( beg === -1 ) { return; }
        const hn1 = origin.slice(beg + 3);
        const end = hn1.indexOf(':');
        const hn2 = end === -1 ? hn1 : hn1.slice(0, end);
        if ( hn2.length === 0 ) { return; }
        const hns = [ hn2 ];
        for ( let pos = 0; ; ) {
            pos = hn2.indexOf('.', pos) + 1;
            if ( pos === 0 ) { break; }
            hns.push(hn2.slice(pos));
        }
        return { hns, i };
    }).filter(a => a);
    if ( entries.length === 0 ) { return; }
    entries[0].hns.push('*');

    const hostnames = entries[0].hns;
    let entities = undefined;
    if ( data.hasEntities ) {
        const ens = [];
        for ( let hn of hostnames ) {
            for (;;) {
                const pos = hn.lastIndexOf('.');
                if ( pos === -1 ) { break; }
                hn = hn.slice(0, pos);
                ens.push(`${hn}.*`);
            }
        }
        ens.sort((a, b) => {
            const d = b.length - a.length;
            if ( d !== 0 ) { return d; }
            return a > b ? -1 : 1;
        });
        entities = ens;
    }

    const selectors = new Set();
    const exceptions = new Set();

    const selectorsFromListIndex = (ilist) => {
        if ( ilist < 0 || ilist >= data.selectorLists.length ) { return; }
        const list = JSON.parse(`[${data.selectorLists[ilist]}]`);
        for ( const iselector of list ) {
            if ( iselector >= 0 ) {
                selectors.add(data.selectors[iselector]);
            } else {
                exceptions.add(data.selectors[~iselector]);
            }
        }
    };

    const selectorsFromHostnames = (haystack, needles) => {
        let listref = -1;
        for ( const needle of needles ) {
            listref = binarySearch(haystack, needle, listref);
            if ( listref >= 0 ) {
                selectorsFromListIndex(data.selectorListRefs[listref]);
            } else {
                listref = ~listref + 1;
            }
        }
    };

    if ( data.hostnames && data.hostnames.length ) {
        selectorsFromHostnames(data.hostnames, hostnames);
        if ( entities ) {
            selectorsFromHostnames(data.hostnames, entities);
        }
    }

    if ( data.regexes && data.regexes.length ) {
        const thisHostname = docloc.hostname || '';
        for ( let i = 0, n = data.regexes.length; i < n; i += 3 ) {
            if ( thisHostname.includes(data.regexes[i]) === false ) { continue; }
            try {
                const re = new RegExp(data.regexes[i+1]);
                if ( re.test(thisHostname) === false ) { continue; }
                selectorsFromListIndex(data.regexes[i+2]);
            } catch(e) {}
        }
    }

    for ( const exc of exceptions ) {
        selectors.delete(exc);
    }

    if ( selectors.size === 0 ) { return; }

    const s = [];
    const p = [];
    for ( const sel of selectors ) {
        if ( sel.startsWith('{') ) {
            try { p.push(JSON.parse(sel)); } catch(e) {}
        } else {
            s.push(sel);
        }
    }

    let css = '';
    if ( s.length !== 0 ) {
        css += s.join(',\n') + ' { display: none !important; }\n';
    }
    for ( const item of p ) {
        if ( item.cssable && Array.isArray(item.action) && item.action[0] === 'style' ) {
            css += `${item.selector} { ${item.action[1]} }\n`;
        }
    }

    if ( !css ) { return; }

    const applyCSS = () => {
        try {
            if ( document.adoptedStyleSheets ) {
                const sheet = new CSSStyleSheet();
                sheet.replaceSync(css);
                document.adoptedStyleSheets.push(sheet);
                return;
            }
        } catch(e) {}
        try {
            const style = document.createElement('style');
            style.type = 'text/css';
            style.setAttribute('data-ubol-cosmetic', data.rulesetId);
            style.textContent = css;
            (document.head || document.documentElement).appendChild(style);
        } catch(e) {}
    };

    if ( document.documentElement ) {
        applyCSS();
    } else {
        document.addEventListener('DOMContentLoaded', applyCSS, { once: true });
    }
})();
