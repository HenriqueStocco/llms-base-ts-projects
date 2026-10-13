# TypeScript

Detail for section 6 of `AGENTS.md`, with examples and procedures. It does not contradict the core; on divergence, the core prevails. The original numbering is kept.

## 6. TypeScript

Follow the project's compiler configuration. Do not loosen checking options to make the code compile.

### 6.1 `any` and `unknown`

- `any` is forbidden by default. Do not use it to work around a compilation error, an incompatibility, or a type not yet understood.
- Rare exception: interoperability with a legacy API or a library without typings, when indispensable. In that case, confine the `any` to the smallest possible scope, comment the reason, and do not let it leak through the public signature.
- `unknown` is the correct type for data whose shape has not yet been proven. Use and encourage it.
- Refine every `unknown` (narrowing, type guard, or schema) before using it.

Incorrect — `any` turns off checking and propagates to whoever consumes the value:

```typescript
function readPort(config: any): number {
  return config.port;
}
```

Correct — `unknown` forces proving the shape before use:

```typescript
function readPort(config: unknown): number {
  if (typeof config !== "object" || config === null || !("port" in config)) {
    throw new Error("Config is missing the `port` field.");
  }

  const { port } = config;

  if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("`port` must be an integer between 1 and 65535.");
  }

  return port;
}
```

Acceptable exception — `any` confined, justified, and validated before leaving:

```typescript
// The legacy client does not publish types. The `any` does not go beyond this function.
function readLegacyVersion(client: any): string {
  const version: unknown = client.getVersion();

  if (typeof version !== "string") {
    throw new Error("Unexpected version returned by the legacy client.");
  }

  return version;
}
```

### 6.2 `type` and `interface`

Neither construct is universally superior.

- Use `type` for unions, intersections, aliases, composition, and utility types.
- Use `interface` for object contracts when extension or implementation by classes brings benefit.
- Do not create a redundant interface or alias for every object. Inferred types and inline types are valid when clear.
- Follow the project's standard when it is coherent.

```typescript
type PaymentMethod = "card" | "bank-transfer" | "cash";

type Page<T> = {
  items: T[];
  nextCursor: string | null;
};

interface Clock {
  now(): Date;
}

class SystemClock implements Clock {
  now(): Date {
    return new Date();
  }
}
```

### 6.3 Generics

- Create a type parameter only when it relates inputs, outputs, or constraints.
- A type parameter that appears only once in the signature relates nothing: remove it, or use `unknown`.
- Prefer inference and simple signatures. Avoid parameters that the caller must specify manually.
- Use `extends` when there is a real requirement on the type.
- Do not create universal generic helpers for simple operations.

Useful — `T` links the item type to the return type; the constraint expresses a real requirement:

```typescript
function sortById<T extends { id: string }>(items: readonly T[]): T[] {
  return [...items].sort((a, b) => a.id.localeCompare(b.id));
}

function groupBy<T, K>(items: readonly T[], getKey: (item: T) => K): Map<K, T[]> {
  const groups = new Map<K, T[]>();

  for (const item of items) {
    const key = getKey(item);
    const group = groups.get(key);

    if (group) {
      group.push(item);
    } else {
      groups.set(key, [item]);
    }
  }

  return groups;
}
```

Incorrect — `T` appears only in the return; it is a disguised cast that validates nothing:

```typescript
function parseJson<T>(text: string): T {
  return JSON.parse(text);
}
```

Correct — return `unknown` and leave validation to whoever knows the contract:

```typescript
function parseJson(text: string): unknown {
  return JSON.parse(text);
}
```

### 6.4 Casts and assertions

- Avoid `as`, `as unknown as`, the non-null assertion (`!`), and any construct that silences the compiler.
- Prefer narrowing, type guards, schemas, and explicit contracts.
- Do not use a cast to pretend that external data was validated.
- When a cast is unavoidable, restrict it to a single point and comment the guarantee that supports it.
- `as const` and `satisfies` do not silence the compiler and are allowed.
- Do not suppress errors with comment directives (`@ts-ignore`, `@ts-expect-error`) without a written justification next to them.

Incorrect:

```typescript
type User = { id: string; email: string };

async function fetchUser(url: string): Promise<User> {
  const response = await fetch(url);

  return (await response.json()) as User;
}

function emailOf(users: User[], id: string): string {
  return users.find((user) => user.id === id)!.email;
}
```

Correct:

```typescript
type User = { id: string; email: string };

function isUser(value: unknown): value is User {
  return (
    typeof value === "object" &&
    value !== null &&
    "id" in value &&
    typeof value.id === "string" &&
    "email" in value &&
    typeof value.email === "string"
  );
}

async function fetchUser(url: string): Promise<User> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Users service responded with ${response.status}.`);
  }

  const body: unknown = await response.json();

  if (!isUser(body)) {
    throw new Error("Unexpected response from the users service.");
  }

  return body;
}

function emailOf(users: readonly User[], id: string): string | undefined {
  return users.find((user) => user.id === id)?.email;
}
```

If the project already adopts a schema library, use it instead of manual type guards.

### 6.5 Domain types and contracts

- TypeScript types do not exist at runtime. Do not presume that a type guarantees the validity of external data.
- Model states so that invalid combinations are not representable. Avoid objects with many optional fields and vague contracts.
- Use branded types or specific types only when there is a concrete risk of mixing up identifiers, units, or states, and the safety gained outweighs the complexity.
- Separate domain types, DTOs, and persistence models when the contracts really differ. Do not duplicate identical types across layers, applications, or packages.
- Restrict mutability (`readonly`, `as const`) when it protects invariants. Do not make every type artificially complex.

Incorrect — allows `status: "paid"` without `paidAt`, or `failureReason` on a paid payment:

```typescript
type Payment = {
  status: "pending" | "paid" | "failed";
  paidAt?: Date;
  failureReason?: string;
};
```

Correct — each state carries exactly the data it has:

```typescript
type Payment =
  | { status: "pending" }
  | { status: "paid"; paidAt: Date }
  | { status: "failed"; failureReason: string };
```

Branded type, when swapping identifiers is a real risk:

```typescript
type UserId = string & { readonly __brand: "UserId" };
type OrderId = string & { readonly __brand: "OrderId" };

function toUserId(value: string): UserId {
  if (value.trim() === "") {
    throw new Error("Empty UserId.");
  }

  // Single, justified cast: the value was just validated at this boundary.
  return value as UserId;
}
```

