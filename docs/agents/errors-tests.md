# Errors and tests

Detail for sections 11 and 12 of `AGENTS.md`, with examples and procedures. It does not contradict the core; on divergence, the core prevails. The original numbering is kept.

## 11. Error handling and validation

- Validate external input at the appropriate boundary (5.1). Once validated, trust the type; do not revalidate the same data in every layer without purpose.
- Distinguish, when the distinction is useful to the consumer: expected error (invalid input, nonexistent resource), domain error (violated rule), infrastructure error (unavailable dependency), and unexpected failure (defect).
- Empty `catch` and silent handling are forbidden.
- Preserve context when propagating: a message with what was being done and the original cause.
- Do not convert a failure into a false success result.
- Do not use a fallback or default value that hides data inconsistency.
- Write messages that are useful to whoever receives them, without exposing internal details, secrets, or sensitive data.
- Do not confuse format validation with authorization or business rules.
- Use the schema library already adopted in the project, when appropriate. Do not introduce a second one.
- Handle dates, time zones, numbers, currency, identifiers, and formats consistently with the existing contracts.
- The strategy is proportional: do not require an error class hierarchy in every project.

Incorrect — the failure disappears and the caller receives a "success" indistinguishable from a nonexistent profile:

```typescript
type Profile = { id: string; name: string };

async function loadProfile(id: string, fetchProfile: (id: string) => Promise<Profile>) {
  try {
    return await fetchProfile(id);
  } catch {
    return null;
  }
}
```

Correct — the failure is propagated with context and cause preserved:

```typescript
type Profile = { id: string; name: string };

async function loadProfile(id: string, fetchProfile: (id: string) => Promise<Profile>): Promise<Profile> {
  try {
    return await fetchProfile(id);
  } catch (error) {
    throw new Error(`Failed to load profile ${id}.`, { cause: error });
  }
}
```

Expected error as part of the contract — the caller is required to handle each case:

```typescript
type QuantityError = "empty" | "not-an-integer" | "out-of-range";

type QuantityResult = { ok: true; value: number } | { ok: false; error: QuantityError };

export function parseQuantity(raw: string): QuantityResult {
  const text = raw.trim();

  if (text === "") {
    return { ok: false, error: "empty" };
  }

  if (!/^\d+$/.test(text)) {
    return { ok: false, error: "not-an-integer" };
  }

  const value = Number(text);

  if (value < 1 || value > 100) {
    return { ok: false, error: "out-of-range" };
  }

  return { ok: true, value };
}
```

Exception and typed result are both valid. Follow the project's predominant style and do not mix the two in the same module without reason.

## 12. Testing strategy

### 12.1 Selection by risk and boundary

| Type | Use for |
| --- | --- |
| Unit | Business rules, transformations, invariants, edge cases. |
| Integration | Real interaction between modules, persistence, and relevant dependencies. |
| Contract | Compatibility between producers, consumers, and formats. |
| E2E | Complete critical flows and observable behavior. |
| Regression | Reproduction of a fixed defect. |
| Property / mutation | When the benefit is proportional (parsers, calculations, broad invariants). |

Do not require all types in every change. Choose the lowest level that actually exercises the risk.

### 12.2 Scenarios to evaluate

According to the functionality:

- Valid paths.
- Missing, malformed, or invalid inputs.
- Boundary values and empty collections.
- Invalid states and disallowed transitions.
- Dependency failure, timeout, and unavailability.
- Authentication and authorization, including access to another user's or organization's resource.
- Concurrency, duplication, and request repetition.
- Atomicity, rollback, and side effects.
- Compatibility and regressions.
- Partial failures and recovery.

### 12.3 Quality

- Test observable results and invariants, not internal details.
- Do not write a test that merely mirrors the current implementation without verifying the contract.
- Do not use a mock to replace precisely the interaction the test is supposed to validate.
- Avoid excessive mocks and brittle tests coupled to the internal structure.
- Line coverage is not a sufficient indicator of quality.
- Prefer deterministic tests: control clock, randomness, order, and network.
- Create a regression test for a relevant fixed defect. When feasible, confirm that it fails without the fix.

Forbidden:

- Removing assertions, weakening or disabling tests to get them to pass.
- Changing a test's expectation just because the implementation failed. Changing the expectation requires that the contract actually changed.
- Declaring tests passed without having run them.

If the environment prevents running some test, report the limitation and what remained unverified.

Example — boundaries and negative scenarios of `parseQuantity` (section 11). `describe`, `it`, and `expect` come from the project's test runner:

```typescript
describe("parseQuantity", () => {
  it("accepts both limits of the range", () => {
    expect(parseQuantity("1")).toEqual({ ok: true, value: 1 });
    expect(parseQuantity("100")).toEqual({ ok: true, value: 100 });
  });

  it("rejects values immediately outside the range", () => {
    expect(parseQuantity("0")).toEqual({ ok: false, error: "out-of-range" });
    expect(parseQuantity("101")).toEqual({ ok: false, error: "out-of-range" });
  });

  it("rejects empty input or input made only of spaces", () => {
    expect(parseQuantity("")).toEqual({ ok: false, error: "empty" });
    expect(parseQuantity("   ")).toEqual({ ok: false, error: "empty" });
  });

  it("rejects anything that is not an unsigned integer", () => {
    expect(parseQuantity("1.5")).toEqual({ ok: false, error: "not-an-integer" });
    expect(parseQuantity("-1")).toEqual({ ok: false, error: "not-an-integer" });
    expect(parseQuantity("1e2")).toEqual({ ok: false, error: "not-an-integer" });
    expect(parseQuantity("ten")).toEqual({ ok: false, error: "not-an-integer" });
  });
});
```

