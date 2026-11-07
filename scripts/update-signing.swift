// Ed25519 key for update signatures. The private key lives only in the login keychain of the
// release machine; the app carries the public key (UpdateCore.signingKeys).
//
//   swift scripts/update-signing.swift generate          new key into the keychain, prints the public key
//   swift scripts/update-signing.swift public            prints the public key of the stored key
//   swift scripts/update-signing.swift sign <dmg>        writes <dmg>.sha256.sig next to <dmg>.sha256
//   swift scripts/update-signing.swift export            prints the private key, for a backup in a password manager
//   swift scripts/update-signing.swift import            reads a private key from stdin into the keychain
//
// What gets signed: UpdateCore.signedMessage(dmgName:hash:), "<dmg file name>\n<sha256 hex>\n".
// Keep both in sync.
import CryptoKit
import Foundation

let service = "io.github.digitaliq.blackholewallpaper.update-signing"
let account = "release"

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

@discardableResult
func security(_ args: [String], input: String? = nil) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    if let input {
        let inp = Pipe()
        p.standardInput = inp
        try? p.run()
        inp.fileHandleForWriting.write(Data(input.utf8))
        try? inp.fileHandleForWriting.close()
    } else {
        try? p.run()
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func storedKey() -> Curve25519.Signing.PrivateKey {
    let (status, b64) = security(["find-generic-password", "-s", service, "-a", account, "-w"])
    guard status == 0, let raw = Data(base64Encoded: b64), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("No update signing key in the keychain (service \(service)). Run: swift scripts/update-signing.swift generate") }
    return key
}

func store(_ key: Curve25519.Signing.PrivateKey) {
    // -w as the last argument without a value makes security read the secret from the prompt,
    // so it never shows up in the process list.
    let b64 = key.rawRepresentation.base64EncodedString()
    let (status, _) = security(["add-generic-password", "-s", service, "-a", account, "-l", "Black Hole Wallpaper update signing", "-w"],
                               input: b64 + "\n" + b64 + "\n")
    guard status == 0 else { fail("Could not store the key in the keychain.") }
}

func message(dmgName: String, hash: String) -> Data { Data("\(dmgName)\n\(hash.lowercased())\n".utf8) }

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "generate":
    if security(["find-generic-password", "-s", service, "-a", account]).0 == 0 {
        fail("A key already exists. Remove it in Keychain Access first if you really want a new one; installed apps then no longer accept updates.")
    }
    let key = Curve25519.Signing.PrivateKey()
    store(key)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(storedKey().publicKey.rawRepresentation.base64EncodedString())
case "export":
    print(storedKey().rawRepresentation.base64EncodedString())
case "import":
    guard let line = readLine(), let raw = Data(base64Encoded: line.trimmingCharacters(in: .whitespaces)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("No valid key on stdin.") }
    store(key)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 2, let dmgPath = args.last else { fail("Usage: sign <dmg>") }
    let dmg = URL(fileURLWithPath: dmgPath)
    let shaFile = URL(fileURLWithPath: dmgPath + ".sha256")
    guard let text = try? String(contentsOf: shaFile, encoding: .utf8),
          let hash = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init), hash.count == 64
    else { fail("Missing or broken \(shaFile.path)") }
    let signature = try storedKey().signature(for: message(dmgName: dmg.lastPathComponent, hash: hash))
    let out = URL(fileURLWithPath: dmgPath + ".sha256.sig")
    try Data((signature.base64EncodedString() + "\n").utf8).write(to: out)
    print(out.path)
default:
    fail("Usage: swift scripts/update-signing.swift generate | public | sign <dmg> | export | import")
}
