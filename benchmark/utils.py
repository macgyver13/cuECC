import itertools
import secrets
from typing import List
from sympy import randprime, isprime


def primes():
    visited = [2]
    for candidate in itertools.count(start=3, step=2):
        if all(
            candidate % prime
            for prime in itertools.takewhile(lambda p: p**2 <= candidate, visited)
        ):
            yield visited[-1]
            visited.append(candidate)


def fast_primes(limit):
    """Generate primes up to limit using Sieve of Eratosthenes - much faster for large ranges.

    WARNING: For very large limits (>10M), this consumes significant memory.
    Consider using generate_large_primes() or generate_crypto_primes() instead.
    """
    if limit < 2:
        return []

    # Prevent excessive memory usage
    if limit > 10_000_000:
        raise ValueError(f"Limit {limit} too large for sieve method. Use generate_large_primes() or generate_crypto_primes() instead.")

    sieve = [True] * (limit + 1)
    sieve[0] = sieve[1] = False

    for i in range(2, int(limit**0.5) + 1):
        if sieve[i]:
            for j in range(i*i, limit + 1, i):
                sieve[j] = False

    return [i for i in range(2, limit + 1) if sieve[i]]


def generate_large_prime(bits: int = 256) -> int:
    """Generate a cryptographically secure random prime of specified bit length."""
    while True:
        candidate = secrets.randbits(bits) | 1  # Ensure odd
        if isprime(candidate):
            return candidate


def generate_crypto_primes(count: int, bits: int = 256) -> List[int]:
    """Generate a list of cryptographically secure random primes.

    Args:
        count: Number of primes to generate
        bits: Bit length of each prime (default: 256 for crypto use)

    Returns:
        List of random primes suitable for cryptographic operations
    """
    return [generate_large_prime(bits) for _ in range(count)]


def generate_range_primes(count: int, min_val: int = 2**255, max_val: int = 2**256) -> List[int]:
    """Generate random primes within a specific range using sympy.

    Args:
        count: Number of primes to generate
        min_val: Minimum value for prime range
        max_val: Maximum value for prime range

    Returns:
        List of random primes in the specified range
    """
    return [randprime(min_val, max_val) for _ in range(count)]
