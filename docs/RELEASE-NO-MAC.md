# Releasing without a Mac

You do not need a Mac. A cloud Mac builds the iPhone app and sends it to TestFlight. A cloud Linux machine builds the Android APK. You create the Apple account, paste a few secrets into a website, and push the code.

Never paste a key, a password, or a certificate into a source file, a README, or a commit. The build machines read them from a secret store. If a key lands in git, delete it at Apple and make a new one. Deleting the commit is not enough.

There are two cloud services. Use one.

- **Codemagic** is the easier path. The website stores the Apple key and fetches the signing certificate for you.
- **GitHub Actions** is the other path. You create a private certificate locker repo and a handful of GitHub secrets. The workflow in `.github/workflows/ios.yml` does the rest.

The Android APK does not need Apple at all. `.github/workflows/android.yml` builds it.

## 1. Join the Apple Developer Program

1. Open [https://developer.apple.com/programs/enroll/](https://developer.apple.com/programs/enroll/) on any computer.
2. Sign in with the Apple ID you want on the store.
3. Enroll as an individual. Pay the yearly fee. Wait for the email that says the membership is active. This can take a day or two.

Write down two things from [https://developer.apple.com/account](https://developer.apple.com/account):

- **Team ID.** It is 10 letters and numbers, on the Membership details page.
- **Your Apple ID email.**

## 2. Create the app record

1. Open [https://appstoreconnect.apple.com](https://appstoreconnect.apple.com).
2. Click **Apps**, then the **+** button, then **New App**.
3. Platform: iOS. Name: `Open UV Bridge`. Primary language: English.
4. Bundle ID: choose **Register a new bundle ID** if you are asked, and enter exactly `net.wa7brm.openuvbridge`.
5. SKU: `openuvbridge`. User access: full.
6. Click **Create**. You do not fill in screenshots yet.

The GitHub Actions workflow also registers this bundle ID and app record if they are missing. The API key needs permission to create apps. Admin can. App Manager often cannot.

## 3. Create an App Store Connect API key

This key is how the cloud Mac talks to Apple. It replaces logging in on a Mac.

1. In App Store Connect, click **Users and Access**.
2. Click the **Integrations** tab. If you do not see it, click **Keys** under that area.
3. Click **App Store Connect API**, then the **+** next to Active keys.
4. Name: `Open UV Bridge CI`. Access: **App Manager**.
5. Click **Generate**.
6. Download the key file. It downloads once. Put it somewhere private on your computer, not in this project folder.
7. On that same page, copy the **Issuer ID** and the **Key ID**. The Key ID is 10 characters. The Issuer ID is a long id with dashes.

Leave the key file closed. You will paste its contents into a website in the next section.

## 4. Recommended: Codemagic

1. Open [https://codemagic.io](https://codemagic.io) and sign up with GitHub.
2. Click **Add application**, choose this repository, and pick the `codemagic.yaml` file when it asks.
3. Open **Team settings** (the gear), then **Integrations**, then **Developer Portal**, then **Connect** under App Store Connect.
4. Name the integration exactly `Open UV Bridge`. The yaml file looks for that name.
5. Paste the Issuer ID, the Key ID, and the contents of the key file into the boxes Codemagic shows. Codemagic stores them. Do not also commit them.
6. Still in Team settings, open **Code signing identities** and confirm Codemagic can fetch an App Store profile for `net.wa7brm.openuvbridge`. The first iOS build does this for you when the integration is connected.
7. Click **Start new build**, choose the workflow **Open UV Bridge iOS**, branch `main`.

When it finishes, App Store Connect shows a build under TestFlight. Processing at Apple takes about fifteen minutes more. You will get an email.

The workflow **Open UV Bridge Android** on the same page builds the APK. Download it from the build artifacts. No Apple account is involved.

## 5. Alternative: GitHub Actions

Use this if you want the build to live next to the code. You still never commit the secrets.

### 5a. A private locker for the certificate

Apple certificates include a private key. Fastlane match keeps that key in a separate private git repo so the next build can reuse it.

1. On GitHub, click **New repository**.
2. Name it `open-uv-bridge-certs`. Set it to **Private**. Do not add a README. Create it.
3. Copy the HTTPS address. It looks like `https://github.com/YOURNAME/open-uv-bridge-certs.git`.
4. Click your GitHub avatar, **Settings**, **Developer settings**, **Personal access tokens**, **Fine-grained tokens**, **Generate new token**.
5. Name it `open-uv-bridge-match`. Repository access: only `open-uv-bridge-certs`. Permissions: Contents **Read and write**. Generate it and copy the token once.

Invent a passphrase you can remember. It locks the certificate repo. Write it in a password manager. This is the match password.

### 5b. Add the secrets

Open this app repository on GitHub. **Settings**, **Secrets and variables**, **Actions**, **New repository secret**. Create each row. The name must match, including capitals.

| Secret name | What you paste |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | The Key ID from step 3 |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID from step 3 |
| `APP_STORE_CONNECT_API_KEY_P8` | The entire contents of the key file, including the first and last lines |
| `APPLE_TEAM_ID` | The 10 character Team ID from step 1 |
| `MATCH_GIT_URL` | The private certs repo address from step 5a |
| `MATCH_GIT_TOKEN` | The fine-grained token from step 5a |
| `MATCH_PASSWORD` | The passphrase you invented |

Do not create a secret called `MATCH_GIT_BASIC_AUTHORIZATION`. The workflow encodes the token itself.

### 5c. Run it

1. Click the **Actions** tab.
2. Open **iOS**.
3. Click **Run workflow**, branch `main`.

The first job runs `swift test` on Linux. The second job generates the Xcode project on a Mac, compiles the app, and, because the secrets exist, creates the certificate in the private locker and uploads to TestFlight.

The workflow trims spaces and line breaks off the certificates URL and token before it uses them. It then checks that the token can see the certs repo. `token rejected (401)` means the token itself was refused. `repo not found or no access (404)` means the URL is wrong or the token cannot see that private repo. If the repo has no branches yet, the workflow pushes an empty first commit on `master`, which is the branch match uses. An empty repo with no commit makes match fail even when the token is valid.

Until the secrets exist, that same workflow still compiles the app with signing turned off and prints that TestFlight was skipped. That is expected.

The **Android** workflow runs on its own. It uploads a debug APK as an artifact named `open-uv-bridge-debug`. On the run page, open the workflow, then **Artifacts**, and download it.

### 5d. Optional signed Android APK

A debug APK is enough to install for yourself. A release APK needs a keystore that you also do not commit.

On any computer with Java installed, in a folder that is not this repo:

```sh
keytool -genkeypair -v -keystore release.jks -alias openuvbridge -keyalg RSA -keysize 2048 -validity 10000
```

Then base64 the file (the command is `base64 -w 0 release.jks` on Linux, or `base64 release.jks` on a Mac) and store these GitHub secrets:

| Secret name | What you paste |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The base64 text of `release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | The store password you just chose |
| `ANDROID_KEY_ALIAS` | `openuvbridge` |
| `ANDROID_KEY_PASSWORD` | The key password you just chose |

The Android workflow then also builds a signed release APK. Keep `release.jks` in your password manager. If you lose it, you cannot update the same Play listing.

## 6. Invite yourself on TestFlight

1. App Store Connect, your app, **TestFlight**.
2. Wait until the build says Ready to Test.
3. The first time, answer the export compliance question. Choose **No**, the app does not use non-exempt encryption. The radio traffic is not encrypted. TLS uses Apple's normal stack, which is exempt.
4. **Internal Testing**, create a group, add your Apple ID email.
5. Install **TestFlight** on the iPhone from the App Store, accept the invite, and install Open UV Bridge.

## 7. What to tell Apple if they ask

Background modes are Bluetooth (the radio link) and location (the beacon while the screen is off). The app hosts a server on the phone so iTAK can connect. It does not ship a server address, a certificate, or a default callsign.

## 8. After it is installed

On the radio: Menu, General Settings, KISS TNC, On. Quit the radio vendor's app. In Open UV Bridge, connect, then tap **Add to iTAK** and import the zip once. Leave that server entry alone when you go from cell service to no service.

The checks for "does iTAK stay connected in the background" and "TCP or TLS" are in [TESTING.md](TESTING.md).
