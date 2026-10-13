# Architecture, naming, formatting, and comments

Detail for sections 7 to 10 of `AGENTS.md`, with examples and procedures. It does not contradict the core; on divergence, the core prevails. The original numbering is kept.

## 7. Architecture and organization of responsibilities

Criteria, not a mandatory structure.

- Organize modules by responsibility or domain, according to the project context.
- Keep dependency boundaries clear and free of cycles.
- Avoid modules that concentrate unrelated responsibilities.
- Extract shared code only with real benefit and concrete use.
- Do not create layers, interfaces, factories, repositories, or services automatically.
- Do not impose Clean Architecture, DDD, MVC, CQRS, or any other pattern. Adopt them when complexity and requirements justify it, or when the project already uses them coherently.
- Do not put business rules in an inappropriate place (handler, UI component, query) just to reduce the number of files.
- Recognize when a module needs to grow, be split, or be reorganized: multiple independent reasons for change, tests that require setting up unrelated context, changes that always touch the same distant points.
- Consider the cost of change: prefer structures that make the next likely change local and cheap.

Proportional separation: pure rule isolated from I/O, with no additional layers:

```typescript
type Order = { id: string; totalCents: number };

type OrderStore = {
  findById(id: string): Promise<Order | undefined>;
  save(order: Order): Promise<void>;
};

// Business rule: no I/O, testable without infrastructure.
export function applyDiscount(totalCents: number, percent: number): number {
  if (percent < 0 || percent > 100) {
    throw new RangeError("The discount must be between 0 and 100.");
  }

  return Math.round(totalCents * (1 - percent / 100));
}

// Orchestration: side effects stay explicit and at the boundary.
export async function applyCoupon(orderId: string, percent: number, orders: OrderStore): Promise<Order> {
  const order = await orders.findById(orderId);

  if (!order) {
    throw new Error(`Order ${orderId} not found.`);
  }

  const updated = { ...order, totalCents: applyDiscount(order.totalCents, percent) };

  await orders.save(updated);

  return updated;
}
```

### 7.1 Monorepos

Do not presume a workspace or orchestration tool.

- Separate applications (deployable units) from packages (reusable code). Applications do not import each other.
- Each package exposes an explicit public API. Do not import internal paths of another package.
- Declare each package's dependencies in its own manifest. Do not depend on packages that are available by accident at the root.
- Keep the dependency graph acyclic and unidirectional: applications depend on packages, never the reverse.
- Share schemas, types, and domain logic when there is more than one real consumer and a single owner of the contract. A shared contract is an API: changing it affects all consumers.
- Do not create an artificial shared package or generic packages that couple unrelated applications.
- Run build, tests, and checks for the changed package **and** for the packages that depend on it, when the project allows.
- Preserve isolation: configuration, secrets, and runtime-specific code of one application do not leak into shared packages.

## 8. Naming and file organization

### 8.1 Names

General standard, subordinate to the project's existing conventions and to the requirements of the framework in use:

- `kebab-case` for files and directories.
- `camelCase` for variables and functions.
- `PascalCase` for classes, types, and interfaces.
- Names that express responsibility. Avoid obscure abbreviations and generic names (`data`, `info`, `manager`, `handler2`).
- Extensions and conventions consistent with the rest of the project.

### 8.2 No contextual redundancy

When the directory already establishes the domain, do not repeat the domain in the file name.

Prefer:

```text
users/
├── service.ts
├── repository.ts
├── schema.ts
├── types.ts
└── tests/
    ├── service.test.ts
    ├── repository.test.ts
    └── schema.test.ts
```

Avoid by default:

```text
users/
├── users.service.ts
├── users.repository.ts
├── users.schema.ts
└── users.types.ts
```

The tree above illustrates naming, not a mandatory set of files (8.4).

### 8.3 Tests

- Prefer a `tests/` directory inside the module, grouping that module's tests.
- Name each test after the module, function, or behavior tested.
- Keep fixtures and helpers close to the tests that use them. Share only with concrete reuse.
- Check the test discovery configuration before creating, moving, or renaming test files.
- Respect the existing convention when it is functional and consistent. Do not migrate the test organization without a request.

### 8.4 No file proliferation

Do not create automatically:

- `types.ts` in every directory.
- `constants.ts` for a single constant.
- `utils.ts`, `helpers.ts`, or `common.ts` as a dumping ground for unrelated functions.
- `index.ts` in every module, with no need for an explicit public API.
- One file per function or declaration.
- Empty layers and files to fulfill a theoretical structure.

Split files by cohesion, responsibility, testability, readability, or dependency boundary — never by habit.

## 9. Formatting and visual readability

Readability is an explicit priority. Do not compress code to reduce lines; do not fragment it with excessive spacing.

- Follow the formatter configured in the project. Do not reformat code outside the scope.
- Keep directly related declarations together, one per line, with no blank line between them.
- Use one blank line between distinct logical blocks: declarations, conditionals, loops, functions, and operations that represent different steps.
- Do not place an independent `if` glued to the previous declaration when they are distinct steps.
- Do not compress a function, conditional, return, or different declarations into a single line.
- Use multiple lines for objects, arrays, calls, and complex conditions when it makes reading easier.
- Do not insert blank lines inside a single cohesive operation.
- Prefer early return when it reduces nesting.

Incorrect:

```typescript
type User = { id: string; name: string; active: boolean };

function listActiveUsers(users: readonly User[]) {
  const activeUsers = users.filter((user) => user.active);
  if (activeUsers.length === 0) return [];
  return activeUsers.map((user) => ({ id: user.id, name: user.name }));
}
```

Correct:

```typescript
type User = { id: string; name: string; active: boolean };

function listActiveUsers(users: readonly User[]) {
  const activeUsers = users.filter((user) => user.active);

  if (activeUsers.length === 0) {
    return [];
  }

  return activeUsers.map((user) => ({
    id: user.id,
    name: user.name,
  }));
}
```

Automatic formatters do not enforce all of these spacing rules between declarations. Use the automatic configuration for what it covers and diff review for the rest.

## 10. Comments and documentation

- Write short, direct, useful comments.
- Comment intent, constraints, non-obvious decisions, invariants, and side effects.
- Do not comment the obvious or restate in words what the code already expresses.
- Update or remove comments that the change made incorrect.
- Do not leave commented-out code or pending-work markers without context.
- Document public APIs, contracts, and relevant behaviors when necessary. Do not create extensive documentation for trivial functions.
- Record significant architectural decisions in an ADR when the context justifies it and the project adopts the practice.
- Do not create documentation that duplicates the code or the core instructions.

