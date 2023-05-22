# Color Sync

This example demonstrates how to set up Couchbase Lite in a peer-to-peer network and seamlessly sync date between devices, with or without the internet.

This enables real-time collaboration and data sharing between nearby devices without the need for an intermediary server or access point. This is an ideal solution for apps that need to maintain continuity between devices even when internet connectivity is not avilable.

[<img alt="Download on the App Store" src="download.svg" width="120" height="40" />](https://apps.apple.com/us/app/simple-color-sync/id6449199482)

## Setup
1. Clone the repo
2. Download the latest [CouchbaseLiteSwift.xcframework](https://www.couchbase.com/downloads/?family=couchbase-lite) and copy it to the project's `Frameworks` directory.
3. Run the app on two or more simulators, phones, or tablets.
4. Tap the screen and the color will change and sync with the other devices.

**NOTE:** The included `gen-credentials.sh` script was used to generate the credentials included with the project. If you want to generate new credentials, run that script again and replace the files in the the project's `credentials` folder with the newly generated files.
