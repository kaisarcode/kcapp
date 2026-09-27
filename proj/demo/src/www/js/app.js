/**
 * kcapp demo script.
 * Summary: Verifies automatic scripting projection for all selected kclibs.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');

    /**
     * Converts text to the byte input accepted by the native bridge.
     * @param text Text to encode.
     * @return Encoded bytes.
     */
    function bytes(text) {
        return new Uint8Array(Array.prototype.map.call(text, function (char) {
            return char.charCodeAt(0);
        }));
    }

    var libraries = Object.keys(window.NativeBridge).filter(function (name) {
        return window.NativeBridge[name] &&
            typeof window.NativeBridge[name].version === 'function';
    }).sort();

    if (libraries.length === 0) {
        output.textContent = 'NativeBridge error: no kclib namespaces found';
        return;
    }

    Promise.all([
        Promise.all(libraries.map(function (name) {
            return window.NativeBridge[name].version().then(function (version) {
                if (typeof version !== 'number' || version <= 0) {
                    throw new Error('invalid ' + name + ' version');
                }
                return {name: name, version: version};
            });
        })),
        window.NativeBridge.http.request({
            method: 'POST',
            target: '/demo',
            headers: [
                {name: 'Host', value: 'example'}
            ],
            body: bytes('test'),
            chunked: 0
        })
    ]).then(function (results) {
        var versions = results[0];
        var requestBytes = results[1];
        if (!(requestBytes instanceof Uint8Array) ||
            requestBytes.length === 0) {
            throw new Error('HTTP request bytes were not projected');
        }

        output.textContent = versions.map(function (entry) {
            return entry.name + ' version: ' + entry.version;
        }).join('\n') +
            '\nhttp request bytes: ' + requestBytes.length +
            '\nAll kcapp kclib bridge tests passed.';
    }).catch(function (error) {
        output.textContent =
            'NativeBridge error: ' +
            (error && error.message ? error.message : String(error));
    });
}());
