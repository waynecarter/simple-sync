# Color Sync

This example demonstrates how to use [Couchbase Lite](https://www.couchbase.com/products/lite/) in a peer-to-peer network and seamlessly sync date between devices, with or without the internet.

This enables real-time collaboration and data sharing between nearby devices without the need for an intermediary server or access point. This is an ideal solution for apps that need to maintain data continuity between devices even when internet connectivity is not avilable.

If you can sync a color, you can sync anything.

[<img alt="Download on the App Store" src="images/download.svg" width="120" height="40" />](https://apps.apple.com/us/app/simple-color-sync/id6449199482)

## Watch the Demo
<a href="https://drive.google.com/file/d/16krxD1DRX_d-FOgRtpYdPrmdQkgPFDXk/view?usp=share_link" target="_blank">
  <img alt="Download on the App Store" src="images/demo-placeholder.png" width="520" height="318" />
</a>

## Explore the Source Code
1. Clone the repo
2. Download the latest [CouchbaseLiteSwift.xcframework](https://www.couchbase.com/downloads/?family=couchbase-lite) and copy it to the project's `Frameworks` directory.
3. Run the app on two or more simulators, phones, or tablets.
4. Tap the screen and the color will change and sync with the other devices.
5. To check out the code, start in the `ViewController` class.

**NOTE:** The included `gen-credentials.sh` script was used to generate the credentials included with the project. If you want to generate new credentials, run that script again and replace the files in the the project's `credentials` folder with the newly generated files.
