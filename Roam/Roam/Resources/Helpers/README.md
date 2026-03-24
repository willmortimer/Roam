Place prebuilt remote helper binaries here for app bundling.

Expected names:
- roam-helper-x86_64-unknown-linux-musl
- roam-helper-aarch64-unknown-linux-musl

Alternative accepted names:
- roam-helper-linux-x86_64
- roam-helper-linux-aarch64

To build them from the Rust workspace:

```sh
cd roam-rs
cross build --release --target x86_64-unknown-linux-musl
cross build --release --target aarch64-unknown-linux-musl
```

Then copy the resulting binaries from:

- `roam-rs/target/x86_64-unknown-linux-musl/release/roam-helper`
- `roam-rs/target/aarch64-unknown-linux-musl/release/roam-helper`

into this folder using one of the expected names above.
