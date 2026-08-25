#!/usr/bin/env python3
"""Generate machine-bound MacWindowButtons activation codes with Ed25519."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import sys
import time
import uuid
from pathlib import Path


PRODUCT_ID = "com.lwb.MacWindowButtons"
TOKEN_PREFIX = "MWB-L1"
PRIVATE_KEY_PATH = Path(__file__).with_name("license_private_key.json")

# RFC 8032 Ed25519 parameters. Keeping this implementation self-contained avoids
# requiring a third-party Python package on the offline issuing machine.
Q = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = (-121665 * pow(121666, Q - 2, Q)) % Q
I = pow(2, (Q - 1) // 4, Q)


def _xrecover(y: int) -> int:
    xx = (y * y - 1) * pow(D * y * y + 1, Q - 2, Q)
    x = pow(xx % Q, (Q + 3) // 8, Q)
    if (x * x - xx) % Q != 0:
        x = (x * I) % Q
    if x % 2 != 0:
        x = Q - x
    return x


BY = (4 * pow(5, Q - 2, Q)) % Q
BASE_POINT = (_xrecover(BY), BY)
IDENTITY = (0, 1)


def _point_add(left: tuple[int, int], right: tuple[int, int]) -> tuple[int, int]:
    x1, y1 = left
    x2, y2 = right
    factor = D * x1 * x2 * y1 * y2
    x3 = (x1 * y2 + x2 * y1) * pow(1 + factor, Q - 2, Q)
    y3 = (y1 * y2 + x1 * x2) * pow(1 - factor, Q - 2, Q)
    return x3 % Q, y3 % Q


def _scalar_multiply(point: tuple[int, int], scalar: int) -> tuple[int, int]:
    result = IDENTITY
    addend = point
    while scalar:
        if scalar & 1:
            result = _point_add(result, addend)
        addend = _point_add(addend, addend)
        scalar >>= 1
    return result


def _encode_point(point: tuple[int, int]) -> bytes:
    x, y = point
    encoded = y | ((x & 1) << 255)
    return encoded.to_bytes(32, "little")


def _expand_seed(seed: bytes) -> tuple[int, bytes]:
    digest = hashlib.sha512(seed).digest()
    scalar_bytes = bytearray(digest[:32])
    scalar_bytes[0] &= 248
    scalar_bytes[31] &= 63
    scalar_bytes[31] |= 64
    return int.from_bytes(scalar_bytes, "little"), digest[32:]


def public_key_for_seed(seed: bytes) -> bytes:
    scalar, _ = _expand_seed(seed)
    return _encode_point(_scalar_multiply(BASE_POINT, scalar))


def sign(seed: bytes, message: bytes) -> bytes:
    scalar, prefix = _expand_seed(seed)
    public_key = public_key_for_seed(seed)
    nonce = int.from_bytes(hashlib.sha512(prefix + message).digest(), "little") % L
    encoded_r = _encode_point(_scalar_multiply(BASE_POINT, nonce))
    challenge = int.from_bytes(
        hashlib.sha512(encoded_r + public_key + message).digest(), "little"
    ) % L
    encoded_s = ((nonce + challenge * scalar) % L).to_bytes(32, "little")
    return encoded_r + encoded_s


def _base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _self_test() -> None:
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
    if public_key_for_seed(seed) != expected_public:
        raise RuntimeError("Ed25519 public-key self-test failed")
    if sign(seed, b"") != expected_signature:
        raise RuntimeError("Ed25519 signing self-test failed")


def initialize_key(force: bool = False) -> tuple[bytes, bytes]:
    if PRIVATE_KEY_PATH.exists() and not force:
        raise RuntimeError(f"private key already exists: {PRIVATE_KEY_PATH}")

    seed = secrets.token_bytes(32)
    public_key = public_key_for_seed(seed)
    payload = {
        "algorithm": "Ed25519",
        "private_seed_base64": base64.b64encode(seed).decode("ascii"),
        "public_key_base64": base64.b64encode(public_key).decode("ascii"),
    }
    PRIVATE_KEY_PATH.write_text(
        json.dumps(payload, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )
    os.chmod(PRIVATE_KEY_PATH, 0o600)
    return seed, public_key


def load_key() -> tuple[bytes, bytes]:
    if not PRIVATE_KEY_PATH.exists():
        raise RuntimeError(
            "private key is missing; run this tool once with --init-key, then "
            "embed the printed public key in the app before building it"
        )
    payload = json.loads(PRIVATE_KEY_PATH.read_text(encoding="utf-8"))
    seed = base64.b64decode(payload["private_seed_base64"], validate=True)
    stored_public = base64.b64decode(payload["public_key_base64"], validate=True)
    if len(seed) != 32 or len(stored_public) != 32:
        raise RuntimeError("private-key file has an invalid length")
    calculated_public = public_key_for_seed(seed)
    if calculated_public != stored_public:
        raise RuntimeError("private-key file is inconsistent")
    return seed, stored_public


def normalize_machine_code(value: str) -> str:
    code = "".join(value.strip().split()).upper()
    if not code.startswith("MWB1-") or len(code) != 45:
        raise ValueError("加密设备码格式不正确，应为 MWB1- 加 40 位十六进制字符")
    if any(character not in "0123456789ABCDEF" for character in code[5:]):
        raise ValueError("加密设备码包含无效字符")
    return code


def generate_license(seed: bytes, machine_code: str, days: int) -> tuple[str, dict]:
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
    signature = sign(seed, payload_data)
    token = f"{TOKEN_PREFIX}.{_base64url(payload_data)}.{_base64url(signature)}"
    return token, payload


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MacWindowButtons 离线激活码生成器")
    parser.add_argument("--init-key", action="store_true", help="生成本机签发私钥")
    parser.add_argument("--force", action="store_true", help="覆盖已有私钥（会使旧激活码失效）")
    parser.add_argument("--machine-code", help="加密设备码；省略时在控制台询问")
    parser.add_argument("--days", type=int, help="激活天数，0 表示永久")
    parser.add_argument("--self-test", action="store_true", help="只运行 Ed25519 自检")
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    _self_test()
    if args.self_test:
        print("Ed25519 self-test: OK")
        return 0

    if args.init_key:
        _, public_key = initialize_key(force=args.force)
        print(f"私钥已保存：{PRIVATE_KEY_PATH}")
        print("请妥善备份，丢失后无法继续签发兼容的激活码。")
        print(f"应用公钥（Base64）：{base64.b64encode(public_key).decode('ascii')}")
        return 0

    seed, _ = load_key()
    machine_code = args.machine_code or input("请输入加密设备码：").strip()
    if args.days is None:
        days = int(input("请输入激活天数（0 表示永久）：").strip())
    else:
        days = args.days
    token, payload = generate_license(seed, machine_code, days)
    validity = "永久" if payload["expires_at"] == 0 else f"{days} 天"
    print(f"\n授权期限：{validity}")
    print(f"许可证编号：{payload['license_id']}")
    print("激活码：")
    print(token)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
