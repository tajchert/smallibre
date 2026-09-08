# Native MTP feasibility probe

2026-09-08. Experimental M1 investigation; this does **not** deliver MTP reader support, uploads, or a backend adoption decision. See [MTP milestones](../handoffs/mtp-readers.md) and [artifact contract](../handoffs/artifact-transport-contract.md).

## Repeatable read-only probe

Run `bash scripts/mtp-probe.sh` from a development checkout on macOS. The script builds the helper and invokes `SmallibreReaderHelper --mtp-probe`; the application does not expose USB I/O. JSON reports visible USB interface count, candidate USB registry/vendor/product IDs, per-candidate status, storage IDs and object metadata. Output can contain personal book filenames: retain it locally, never commit owner inventories.

The implementation uses the system IOUSBHost framework directly from Swift. Apple describes it as [user-space USB access from applications](https://developer.apple.com/documentation/iousbhost/). API details were checked against Xcode 26.6's SDK headers `IOUSBHostObject.h`, `IOUSBHostInterface.h`, `IOUSBHostPipe.h` and `AppleUSBDescriptorParsing.h`, and typechecked locally:

- `IOServiceGetMatchingServices` enumerates `IOUSBHostInterface` services; registry properties select Amazon vendor `0x1949`, still-image interface class/subclass/protocol `6/1/1`. Nonstandard interfaces remain unsupported; an interface descriptor is not proof of an MTP Kindle.
- `IOUSBHostInterface(__ioService:options:queue:interestHandler:)` opens with no seize option. The SDK documents exclusive ownership and failure when a user client already exists. `destroy()` releases the user client on every successful-open path.
- `IOUSBGetNextEndpointDescriptor` locates bulk input/output endpoints; `copyPipe(withAddress:)` and the imported `__sendIORequest(with:bytesTransferred:completionTimeout:)` perform synchronous bulk I/O.
- Only OpenSession, GetStorageIDs, GetObjectHandles, GetObjectInfo and CloseSession command codes are representable. USB command OUT traffic is necessary for these reads; no SendObject, DeleteObject, format, reset, configuration change, driver detachment or seize operation is present.
- Transactions validate lengths, container types, transaction IDs, operation codes, success responses, counted arrays and bounded UTF-16 filenames. Limits: 1 MiB containers, 16 storages, 1,000 objects, 2,048 transactions, 256 visible interfaces, 4 candidates, 32 endpoints, 260 fragments/container, 2-second bulk-operation timeout and 30-second overall probe deadline. A limit or unsupported reply fails the diagnostic; it does not silently claim a complete inventory.
- The exchange coordinator marks synchronization uncertain before sending a command, and restores it only after the complete successful response. A local dataset validation failure (such as too many handles or an unsafe filename) after that response attempts CloseSession; successful cleanup reports `inventoryFailedSessionClosed`. A failed transaction releases the USB client without another protocol command; `inventoryFailedRemoteSessionClosureUnconfirmed` explicitly distinguishes this from a confirmed remote CloseSession. Session-close success is required for `readOnlyInventoryCompleted`. Deadline exhaustion may also prevent a cleanup command; it never implies successful closure. Device recovery after interrupted sessions still needs testing. A blocking kernel call can outlive a deadline; helper process isolation remains necessary and no prompt cancellation claim is made.

The probe inventories metadata only, without reading book bytes or hashing them. Names, object sizes and handles remain unverified hints. No persistent cache, transport adapter, app inventory UI or helper session IPC is connected to this experiment. The CLI entry is a diagnostic, and must not be used to infer permission to upload or delete.

## Evidence and open gates

On macOS 26.6.2 (25G83), sandboxed system USB enumeration was empty. A separately authorized read-only `ioreg -r -c IOUSBHostInterface -l` outside the sandbox also returned no entries. No MTP Kindle model, firmware, interface opening, storage listing or object listing has been demonstrated. The JSON status `noVisibleUSBInterfacesAccessUnverified` deliberately distinguishes this from successful hardware certification. The integrated helper probe returned `interfacesSeen: 0`, empty `devices`, and `noVisibleUSBInterfacesAccessUnverified`. All nine authored packet and session lifecycle tests passed using `swift test --filter MTP` in the main package. Fake wire tests cover successful responses followed by local handle-count/name failures, missing/failed/mismatched responses, and failed CloseSession without retry. Native API linking/typechecking and authored packet tests establish only local implementation properties.

Before selecting a shipping backend, attach an authorized identified Kindle and record model, firmware, macOS, USB vendor/product IDs and connection mode. Test clean open/list/close, competing client, sleep, disconnection and reconnection; record latency, peak memory and cancellation behavior. Do not put serial numbers or book inventories in tracked evidence. A competing client must produce an access failure, never be seized. Hardware transfer authorization is separate; this probe cannot perform transfers.

| Candidate | Current evidence | Remaining decision evidence |
| --- | --- | --- |
| Native Swift + IOUSBHost | Compiles against system framework; bounded read-only implementation; no downloaded dependency | Named Kindle access/protocol compatibility, quirks, cancellation and release-size measurement |
| Pinned libmtp/libusb wrapper | No code adopted or binaries built | Same-device comparison, pinned revisions, measured size, required license notices, packaging/load paths and maintenance cost |

No libmtp/libusb dependency has been installed, vendored or selected. Existing native-only policy remains in effect. M1 is incomplete until hardware proves read-only operation and the owner selects a backend using comparative evidence. MTP send and conversion-to-device remain unavailable.


Final integrated local check: `SmallibreReaderHelper --mtp-probe` emitted valid JSON with `noVisibleUSBInterfacesAccessUnverified`, zero visible interfaces and no candidates. No Kindle volume was visible either. The user's Paperwhite/possible 5.19.6 report does not establish its connection mode. The full package suite passed 70 tests with five opt-in skips; release packaging and strict ad-hoc signature verification passed. The combined feasibility increment adds 197,504 logical bundle bytes (5,901,172 total) over the shared-contract build; this is not a same-device native-versus-libmtp benchmark. No device files were read or written during the no-interface probe.
