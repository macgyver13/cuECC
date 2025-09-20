"""Optimized CPU implementation using coincurve (libsecp256k1 bindings)."""

from contextlib import AbstractContextManager, nullcontext
from typing import List

import coincurve

from bindings.ecc import EccProtocol
from bindings.utils import Point


class EccOptimized(EccProtocol):
    """High-performance CPU implementation using coincurve (libsecp256k1)."""

    def __init__(self) -> None:
        # Coincurve uses libsecp256k1 internally - no additional setup needed
        pass

    def get_public_key_by_private_key(
        self,
        private_keys: List[int],
        kernel_context: AbstractContextManager[None] | None = None,
    ) -> List[Point]:
        if kernel_context is None:
            kernel_context = nullcontext()

        with kernel_context:
            public_keys = []
            for priv_key in private_keys:
                # Convert to 32-byte format
                priv_bytes = priv_key.to_bytes(32, 'big')

                # Create private key object
                privkey = coincurve.PrivateKey(priv_bytes)

                # Get public key
                pubkey = privkey.public_key

                # Get uncompressed public key coordinates
                pubkey_bytes = pubkey.format(compressed=False)

                # Extract x, y coordinates (skip 0x04 prefix)
                x = int.from_bytes(pubkey_bytes[1:33], 'big')
                y = int.from_bytes(pubkey_bytes[33:65], 'big')

                public_keys.append(Point(x=x, y=y))

        return public_keys