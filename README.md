<div align="center">

# Mac Duo

**Wish you could bring the iPhone Duo effect to your MacBook?**

https://github.com/user-attachments/assets/3ea3b098-c6d2-4398-8f3a-e9087bbb33f2

Close the lid and watch your screen content tilt, blur, and fade as it moves.  
Mac Duo adds this effect to your MacBook, with controls in the menu bar.

**Available in:** English and Simplified Chinese (简体中文).

<img src="./assets/menu.png" width="400" alt="Mac Duo menu">

</div>

<hr>

With the default settings, it's recommended to view the effect in front of your MacBook.

- **Metal rendering:** Uses GPU rendering to apply perspective, blur, and dimming as the lid closes.
- **Live screen content:** Uses ScreenCaptureKit to capture and render screen content in real time.
- **Adjustable perspective:** Tweak the perspective to suit your viewing position and make the effect look more natural.


> [!NOTE]
> Mac Duo is completely **free** to use. Whether you use the app or reuse its code in your projects, please consider [sponsoring me](https://github.com/sponsors/sumimakito) if you find it helpful.
>
> Special thanks to our team at [Moeru AI](https://github.com/moeru-ai) for sponsoring the Apple Developer Program membership used to sign and notarize the prebuilt app here.

## Download

[Download DMG](https://github.com/sumimakito/Mac-Duo/releases/download/dev/Mac-Duo-dev.dmg) | [Download ZIP](https://github.com/sumimakito/Mac-Duo/releases/download/dev/Mac-Duo-dev.zip)

These downloads contain the latest [development build](https://github.com/sumimakito/Mac-Duo/releases/tag/dev) for Apple Silicon and Intel Macs.

Requires macOS 14 or later and a MacBook with a compatible lid angle sensor.
Grant Screen Recording permission when prompted to enable the effect.

## Build

Requires Xcode with Swift 6.0 or later. Run from the project directory:

```sh
./build.sh
```

The script creates `build/Mac Duo.app`. Open it from Finder, or build and launch with:

```sh
./build.sh --run
```

Install it into `/Applications` and launch it from there with:

```sh
./build.sh --install --run
```

### Keeping the Screen Recording permission

macOS ties the Screen Recording grant to the app's designated requirement. An
ad-hoc signature puts the binary's own hash in there, so every rebuild looks
like a different app and the permission has to be granted again — until it is,
the effect has nothing to draw and macOS re-asks each time the lid passes the
start angle.

Signing with a certificate pins the requirement to the certificate instead, and
the grant survives rebuilds. A self-signed one is enough:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/macduo-key.pem -out /tmp/macduo-cert.pem \
  -subj "/CN=Mac Duo Dev" \
  -addext "basicConstraints=critical,CA:true" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -inkey /tmp/macduo-key.pem -in /tmp/macduo-cert.pem \
  -out /tmp/macduo.p12 -name "Mac Duo Dev" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout pass:macduo
security import /tmp/macduo.p12 -k ~/Library/Keychains/login.keychain-db \
  -P macduo -T /usr/bin/codesign
```

`build.sh` picks the certificate up by name from then on. The certificate does
not need to be trusted for this, and `SIGN_IDENTITY` still overrides it.

After the first build with a new identity, clear the stale entries and grant the
permission once:

```sh
tccutil reset ScreenCapture to.maki.MacDuo
```

## Known limitations

- Only MacBooks with a compatible lid angle sensor can use the effect. The app reports when no sensor is available.
- The sensor must be one macOS marks as built-in. An external display with a similar sensor is ignored.
- The effect applies only to the built-in display.
- The effect stops when macOS sleeps as the lid closes.
- Clicks pass through the effect to the apps underneath.

## Acknowledgements

This project is built with AI assistance.

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 Makito.

See [NOTICE](NOTICE) for attribution.
