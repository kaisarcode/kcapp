/**
 * kcapp demo script.
 * Summary: Verifies one explicit application bridge method.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');

    window.NativeBridge.redp2pVersion({}).then(function (result) {
        if (!result || typeof result.version !== 'number' || result.version <= 0) {
            throw new Error('invalid redp2p version');
        }

        output.textContent =
            'redp2p version: ' + result.version +
            '\nNativeBridge loaded successfully.';
    }).catch(function (error) {
        output.textContent =
            'NativeBridge error: ' +
            (error && error.message ? error.message : String(error));
    });
}());
