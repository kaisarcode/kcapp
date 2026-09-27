/**
 * kcapp demo script.
 * Summary: Verifies automatic scripting projection for one kclib.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');

    window.NativeBridge.redp2p.version().then(function (version) {
        if (typeof version !== 'number' || version <= 0) {
            throw new Error('invalid redp2p version');
        }

        output.textContent =
            'redp2p version: ' + version +
            '\nNativeBridge loaded successfully.';
    }).catch(function (error) {
        output.textContent =
            'NativeBridge error: ' +
            (error && error.message ? error.message : String(error));
    });
}());
