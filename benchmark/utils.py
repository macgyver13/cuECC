import itertools


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
    """Generate primes up to limit using Sieve of Eratosthenes - much faster for large ranges."""
    if limit < 2:
        return []

    sieve = [True] * (limit + 1)
    sieve[0] = sieve[1] = False

    for i in range(2, int(limit**0.5) + 1):
        if sieve[i]:
            for j in range(i*i, limit + 1, i):
                sieve[j] = False

    return [i for i in range(2, limit + 1) if sieve[i]]
