#!/usr/bin/env python3

import base64
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_license as issuer


TEST_PASSWORD = "correct horse battery staple".encode("utf-8")
TEST_MACHINE_CODE = "MWB1-" + "A1" * 20


class LicenseGeneratorTests(unittest.TestCase):
    def test_rfc_8032_self_test(self) -> None:
        issuer._self_test()

    def test_encrypted_key_round_trip_and_wrong_password(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            key_path = Path(directory) / "private.pem"
            _, public_key = issuer.initialize_key(TEST_PASSWORD, path=key_path)

            contents = key_path.read_bytes()
            self.assertIn(b"BEGIN ENCRYPTED PRIVATE KEY", contents)
            self.assertEqual(key_path.stat().st_mode & 0o777, 0o600)
            _, loaded_public = issuer.load_key(TEST_PASSWORD, key_path)
            self.assertEqual(loaded_public, public_key)
            with self.assertRaisesRegex(RuntimeError, "口令错误"):
                issuer.load_key(b"wrong password", key_path)

    def test_migration_preserves_public_key_and_removes_plaintext(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            legacy_path = root / "private.json"
            encrypted_path = root / "private.pem"
            seed = bytes(range(32))
            private_key = issuer.Ed25519PrivateKey.from_private_bytes(seed)
            public_key = issuer._public_key_bytes(private_key)
            legacy_path.write_text(
                json.dumps(
                    {
                        "algorithm": "Ed25519",
                        "private_seed_base64": base64.b64encode(seed).decode("ascii"),
                        "public_key_base64": base64.b64encode(public_key).decode("ascii"),
                    }
                ),
                encoding="utf-8",
            )

            migrated_public = issuer.migrate_legacy_key(
                TEST_PASSWORD,
                legacy_path=legacy_path,
                encrypted_path=encrypted_path,
            )

            self.assertEqual(migrated_public, public_key)
            self.assertFalse(legacy_path.exists())
            _, loaded_public = issuer.load_key(TEST_PASSWORD, encrypted_path)
            self.assertEqual(loaded_public, public_key)

    def test_generated_license_signature_and_permanent_expiry(self) -> None:
        private_key = issuer.Ed25519PrivateKey.generate()
        token, payload = issuer.generate_license(
            private_key,
            TEST_MACHINE_CODE,
            days=0,
        )
        prefix, encoded_payload, encoded_signature = token.split(".")
        payload_data = base64.urlsafe_b64decode(
            encoded_payload + "=" * (-len(encoded_payload) % 4)
        )
        signature = base64.urlsafe_b64decode(
            encoded_signature + "=" * (-len(encoded_signature) % 4)
        )

        self.assertEqual(prefix, issuer.TOKEN_PREFIX)
        self.assertEqual(json.loads(payload_data), payload)
        self.assertEqual(payload["expires_at"], 0)
        private_key.public_key().verify(signature, payload_data)

    def test_rejects_invalid_machine_code_and_negative_days(self) -> None:
        private_key = issuer.Ed25519PrivateKey.generate()
        with self.assertRaises(ValueError):
            issuer.generate_license(private_key, "invalid", days=30)
        with self.assertRaises(ValueError):
            issuer.generate_license(private_key, TEST_MACHINE_CODE, days=-1)


if __name__ == "__main__":
    unittest.main()
