# Simple P2P

This example demonstrates how to set up data synchronization with Couchbase Lite in a peer-to-peer network. The example allows for seamless data syncing across a variety of network interfaces, including Wi-Fi networks, device-to-device Wi-Fi, and Bluetooth.

This enables real-time collaboration and data sharing between nearby devices without the need for an intermediary server or access point, making it an ideal solution for apps that need to sync data with or without the internet.

## Setup
1. Clone the repo
2. Download the latest [CouchbaseLiteSwift.xcframework](https://www.couchbase.com/downloads/?family=couchbase-lite) and copy it to the project's `Frameworks` directory.
3. Run the app on two or more simulators, phones, or tablets.
4. Tap the screen and the color will change and sync with the other devices.

**NOTE:** The included `gen-credentials.sh` script was used to generate the credentials included in the project and the included credentials can be used as-is for demo purposes. If you want to generate new credentials, run that script again and replace the files in the the project's `credentials` folder with the newly generated files.
