// Generates the Apple SIWA client_secret JWT required by Supabase.
// Valid for 6 months (Apple's maximum). Re-run when it expires.
const crypto = require('crypto');
const fs = require('fs');

const privateKey = fs.readFileSync('G:/Projects/Keys/GymSync/AuthKey_J8XSL927WY.p8', 'utf8');
const teamId    = '299EBDGH62';
const keyId     = 'J8XSL927WY';
const clientId  = 'app.gymsync.web';

const now = Math.floor(Date.now() / 1000);
const exp = now + 15777000; // 6 months

const header  = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyId })).toString('base64url');
const payload = Buffer.from(JSON.stringify({ iss: teamId, iat: now, exp, aud: 'https://appleid.apple.com', sub: clientId })).toString('base64url');

const data = `${header}.${payload}`;
const sign = crypto.createSign('SHA256');
sign.update(data);
// ieee-p1363 produces the raw R||S signature format required by JWT ES256
const sig = sign.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' }, 'base64url');

console.log(`\nPaste this into Supabase → Apple → Secret Key:\n`);
console.log(`${data}.${sig}\n`);
console.log(`Expires: ${new Date(exp * 1000).toISOString()}`);
