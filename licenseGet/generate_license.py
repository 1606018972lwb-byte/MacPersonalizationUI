#!/usr/bin/env python3
"""Generate machine-bound MacWindowButtons activation codes with Ed25519."""

from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError:
    serialization = None
    Ed25519PrivateKey = None


PRODUCT_ID = "com.lwb.MacWindowButtons"
TOKEN_PREFIX = "MWB-L1"
KEY_DIRECTORY = Path(__file__).resolve().parent
PRIVATE_KEY_PATH = KEY_DIRECTORY / "license_private_key.pem"
LEGACY_PRIVATE_KEY_PATH = KEY_DIRECTORY / "license_private_key.json"
MINIMUM_PASSWORD_LENGTH = 12


def require_cryptography() -> None:
    if serialization is None or Ed25519PrivateKey is None:
        raise RuntimeError(
            "缺少 cryptography 依赖。请先运行：\n"
            "python3 -m pip install -r licenseGet/requirements.txt"
        )


def _public_key_bytes(private_key: Any) -> bytes:
    return private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )


def _base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _self_test() -> None:
    require_cryptography()
    # RFC 8032 section 7.1, test vector 1 (empty message).
    seed = bytes.fromhex(
        "9d61b19deffd5a60ba844af492ec2cc4"
        "4449c5697b326919703bac031cae7f60"
    )
    expected_public = bytes.fromhex(
        "d75a980182b10ab7d54bfed3c964073a"
        "0ee172f3daa62325af021a68f707511a"
    )
    expected_signature = bytes.fromhex(
        "e5564300c360ac729086e2cc806e828a"
        "84877f1eb8e5d974d873e06522490155"
        "5fb8821590a33bacc61e39701cf9b46b"
        "d25bf5f0595bbe24655141438e7a100b"
    )
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    if _public_key_bytes(private_key) != expected_public:
        raise RuntimeError("Ed25519 public-key self-test failed")
    if private_key.sign(b"") != expected_signature:
        raise RuntimeError("Ed25519 signing self-test failed")


def prompt_new_password() -> bytes:
    password = getpass.getpass(
        f"请设置私钥口令（至少 {MINIMUM_PASSWORD_LENGTH} 个字符）："
    )
    if len(password) < MINIMUM_PASSWORD_LENGTH:
        raise ValueError(f"私钥口令至少需要 {MINIMUM_PASSWORD_LENGTH} 个字符")
    confirmation = getpass.getpass("请再次输入私钥口令：")
    if password != confirmation:
        raise ValueError("两次输入的私钥口令不一致")
    return password.encode("utf-8")


def prompt_existing_password() -> bytes:
    password = getpass.getpass("请输入私钥口令：")
    if not password:
        raise ValueError("私钥口令不能为空")
    return password.encode("utf-8")


def _write_encrypted_key(private_key: Any, password: bytes, path: Path) -> None:
    if len(password.decode("utf-8")) < MINIMUM_PASSWORD_LENGTH:
        raise ValueError(f"私钥口令至少需要 {MINIMUM_PASSWORD_LENGTH} 个字符")
    pem_data = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.BestAvailableEncryption(password),
    )
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=str(path.parent),
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(pem_data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
        raise


def initialize_key(
    password: bytes,
    force: bool = False,
    path: Path = PRIVATE_KEY_PATH,
) -> tuple[Any, bytes]:
    require_cryptography()
    if path.exists() and not force:
        raise RuntimeError(f"加密私钥已存在：{path}")
    if LEGACY_PRIVATE_KEY_PATH.exists() and path == PRIVATE_KEY_PATH and not force:
        raise RuntimeError(
            "检测到旧版明文 JSON 私钥，请运行 --migrate-key，不能重新生成私钥"
        )

    private_key = Ed25519PrivateKey.generate()
    public_key = _public_key_bytes(private_key)
    _write_encrypted_key(private_key, password, path)
    return private_key, public_key


def load_key(
    password: bytes,
    path: Path = PRIVATE_KEY_PATH,
) -> tuple[Any, bytes]:
    require_cryptography()
    if not path.exists():
        if LEGACY_PRIVATE_KEY_PATH.exists() and path == PRIVATE_KEY_PATH:
            raise RuntimeError(
                "检测到旧版明文 JSON 私钥。请先运行 --migrate-key 完成加密迁移"
            )
        raise RuntimeError(f"加密私钥不存在：{path}")

    try:
        private_key = serialization.load_pem_private_key(
            path.read_bytes(),
            password=password,
        )
    except (TypeError, ValueError) as error:
        raise RuntimeError("私钥口令错误或加密私钥文件已损坏") from error
    if not isinstance(private_key, Ed25519PrivateKey):
        raise RuntimeError("私钥不是 Ed25519 PKCS#8 密钥")
    return private_key, _public_key_bytes(private_key)


def _load_legacy_key(path: Path = LEGACY_PRIVATE_KEY_PATH) -> tuple[Any, bytes]:
    require_cryptography()
    if not path.exists():
        raise RuntimeError(f"旧版 JSON 私钥不存在：{path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        seed = base64.b64decode(payload["private_seed_base64"], validate=True)
        stored_public = base64.b64decode(
            payload["public_key_base64"],
            validate=True,
        )
    except (KeyError, ValueError, json.JSONDecodeError) as error:
        raise RuntimeError("旧版 JSON 私钥格式无效") from error
    if len(seed) != 32 or len(stored_public) != 32:
        raise RuntimeError("旧版 JSON 私钥长度无效")
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    if _public_key_bytes(private_key) != stored_public:
        raise RuntimeError("旧版 JSON 私钥中的公钥与私钥不匹配")
    return private_key, stored_public


def migrate_legacy_key(
    password: bytes,
    legacy_path: Path = LEGACY_PRIVATE_KEY_PATH,
    encrypted_path: Path = PRIVATE_KEY_PATH,
    remove_legacy: bool = True,
) -> bytes:
    if encrypted_path.exists():
        raise RuntimeError(f"加密私钥已存在，拒绝覆盖：{encrypted_path}")
    private_key, public_key = _load_legacy_key(legacy_path)
    try:
        _write_encrypted_key(private_key, password, encrypted_path)
        _, verified_public = load_key(password, encrypted_path)
        if verified_public != public_key:
            raise RuntimeError("迁移后的加密私钥验证失败")
    except Exception:
        encrypted_path.unlink(missing_ok=True)
        raise RuntimeError("迁移后的加密私钥验证失败，旧文件已保留")
    if remove_legacy:
        legacy_path.unlink()
    return public_key


def normalize_machine_code(value: str) -> str:
    code = "".join(value.strip().split()).upper()
    if not code.startswith("MWB1-") or len(code) != 45:
        raise ValueError("加密设备码格式不正确，应为 MWB1- 加 40 位十六进制字符")
    if any(character not in "0123456789ABCDEF" for character in code[5:]):
        raise ValueError("加密设备码包含无效字符")
    return code


def generate_license(
    private_key: Any,
    machine_code: str,
    days: int,
) -> tuple[str, dict]:
    if days < 0:
        raise ValueError("激活天数不能为负数")
    issued_at = int(time.time())
    expires_at = 0 if days == 0 else issued_at + days * 24 * 60 * 60
    payload = {
        "expires_at": expires_at,
        "issued_at": issued_at,
        "license_id": uuid.uuid4().hex,
        "machine": normalize_machine_code(machine_code),
        "product": PRODUCT_ID,
        "v": 1,
    }
    payload_data = json.dumps(
        payload,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    signature = private_key.sign(payload_data)
    token = f"{TOKEN_PREFIX}.{_base64url(payload_data)}.{_base64url(signature)}"
    return token, payload


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MacWindowButtons 离线激活码生成器")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--init-key", action="store_true", help="生成加密签发私钥")
    actions.add_argument(
        "--migrate-key",
        action="store_true",
        help="把旧版明文 JSON 私钥迁移为加密 PKCS#8，并删除旧文件",
    )
    actions.add_argument("--self-test", action="store_true", help="只运行 Ed25519 自检")
    parser.add_argument("--force", action="store_true", help="覆盖已有私钥（会使旧激活码失效）")
    parser.add_argument("--machine-code", help="加密设备码；省略时在控制台询问")
    parser.add_argument("--days", type=int, help="激活天数，0 表示永久")
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    if args.force and not args.init_key:
        raise ValueError("--force 只能与 --init-key 一起使用")
    _self_test()
    if args.self_test:
        print("Ed25519 self-test: OK")
        return 0

    if args.migrate_key:
        password = prompt_new_password()
        public_key = migrate_legacy_key(password)
        print(f"迁移完成，加密私钥已保存：{PRIVATE_KEY_PATH}")
        print(f"旧版明文私钥已删除：{LEGACY_PRIVATE_KEY_PATH}")
        print(f"应用公钥（Base64）：{base64.b64encode(public_key).decode('ascii')}")
        return 0

    if args.init_key:
        password = prompt_new_password()
        _, public_key = initialize_key(password, force=args.force)
        print(f"加密私钥已保存：{PRIVATE_KEY_PATH}")
        print("请分别备份私钥文件和口令，丢失任一项都无法继续签发。")
        print(f"应用公钥（Base64）：{base64.b64encode(public_key).decode('ascii')}")
        return 0

    password = prompt_existing_password()
    private_key, _ = load_key(password)
    machine_code = args.machine_code or input("请输入加密设备码：").strip()
    if args.days is None:
        days = int(input("请输入激活天数（0 表示永久）：").strip())
    else:
        days = args.days
    token, payload = generate_license(private_key, machine_code, days)
    validity = "永久" if payload["expires_at"] == 0 else f"{days} 天"
    print(f"\n授权期限：{validity}")
    print(f"许可证编号：{payload['license_id']}")
    print("激活码：")
    print(token)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
