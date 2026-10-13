# TypeScript

Detalhe das seções 6 de `AGENTS.md`, com exemplos e procedimentos. Não contradiz o núcleo; em caso de divergência, vale o núcleo. A numeração original foi mantida.

## 6. TypeScript

Seguir a configuração do compilador do projeto. Não afrouxar opções de verificação para fazer o código compilar.

### 6.1 `any` e `unknown`

- `any` é proibido por padrão. Não usar para contornar erro de compilação, incompatibilidade ou tipo ainda não compreendido.
- Exceção rara: interoperabilidade com API legada ou biblioteca sem tipagem, quando indispensável. Nesse caso, confinar o `any` ao menor trecho possível, comentar o motivo e não deixá-lo vazar pela assinatura pública.
- `unknown` é o tipo correto para dados cujo formato ainda não foi comprovado. Usar e incentivar.
- Refinar todo `unknown` (narrowing, type guard ou schema) antes de usá-lo.

Incorreto — `any` desliga a verificação e se propaga para quem consome o valor:

```typescript
function readPort(config: any): number {
  return config.port;
}
```

Correto — `unknown` obriga a provar o formato antes do uso:

```typescript
function readPort(config: unknown): number {
  if (typeof config !== "object" || config === null || !("port" in config)) {
    throw new Error("Configuração sem o campo `port`.");
  }

  const { port } = config;

  if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("`port` deve ser um inteiro entre 1 e 65535.");
  }

  return port;
}
```

Exceção aceitável — `any` confinado, justificado e validado antes de sair:

```typescript
// O cliente legado não publica tipos. O `any` não ultrapassa esta função.
function readLegacyVersion(client: any): string {
  const version: unknown = client.getVersion();

  if (typeof version !== "string") {
    throw new Error("Versão inesperada retornada pelo cliente legado.");
  }

  return version;
}
```

### 6.2 `type` e `interface`

Nenhuma das duas construções é universalmente superior.

- Usar `type` para unions, intersections, aliases, composição e tipos utilitários.
- Usar `interface` para contratos de objeto quando a extensão ou a implementação por classes trouxer benefício.
- Não criar interface ou alias redundante para cada objeto. Tipos inferidos e tipos inline são válidos quando claros.
- Seguir o padrão do projeto quando ele for coerente.

```typescript
type PaymentMethod = "card" | "pix" | "boleto";

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

- Criar parâmetro de tipo somente quando ele relaciona entradas, saídas ou restrições.
- Um parâmetro de tipo que aparece uma única vez na assinatura não relaciona nada: remover, ou usar `unknown`.
- Preferir inferência e assinaturas simples. Evitar parâmetros que o chamador precisa informar manualmente.
- Usar `extends` quando houver exigência real sobre o tipo.
- Não criar helpers genéricos universais para operações simples.

Útil — `T` liga o tipo dos itens ao do retorno; a constraint expressa uma exigência real:

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

Incorreto — `T` aparece só no retorno; é um cast disfarçado que nada valida:

```typescript
function parseJson<T>(text: string): T {
  return JSON.parse(text);
}
```

Correto — devolver `unknown` e deixar a validação para quem conhece o contrato:

```typescript
function parseJson(text: string): unknown {
  return JSON.parse(text);
}
```

### 6.4 Casts e asserções

- Evitar `as`, `as unknown as`, non-null assertion (`!`) e qualquer construção que silencie o compilador.
- Preferir narrowing, type guards, schemas e contratos explícitos.
- Não usar cast para fingir que um dado externo foi validado.
- Quando um cast for inevitável, restringi-lo a um ponto e comentar a garantia que o sustenta.
- `as const` e `satisfies` não silenciam o compilador e são permitidos.
- Não suprimir erros com diretivas de comentário (`@ts-ignore`, `@ts-expect-error`) sem justificativa escrita ao lado.

Incorreto:

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

Correto:

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
    throw new Error(`Serviço de usuários respondeu ${response.status}.`);
  }

  const body: unknown = await response.json();

  if (!isUser(body)) {
    throw new Error("Resposta inesperada do serviço de usuários.");
  }

  return body;
}

function emailOf(users: readonly User[], id: string): string | undefined {
  return users.find((user) => user.id === id)?.email;
}
```

Se o projeto já adota uma biblioteca de schemas, usá-la no lugar de type guards manuais.

### 6.5 Tipos de domínio e contratos

- Tipos TypeScript não existem em runtime. Não presumir que um tipo garante a validade de um dado externo.
- Modelar estados de forma que combinações inválidas não sejam representáveis. Evitar objetos com muitos opcionais e contratos vagos.
- Usar branded types ou tipos específicos somente quando houver risco concreto de confundir identificadores, unidades ou estados, e a segurança obtida compensar a complexidade.
- Separar tipos de domínio, DTOs e modelos de persistência quando os contratos forem realmente diferentes. Não duplicar tipos idênticos entre camadas, aplicações ou pacotes.
- Restringir mutabilidade (`readonly`, `as const`) quando proteger invariantes. Não tornar todo tipo artificialmente complexo.

Incorreto — permite `status: "paid"` sem `paidAt`, ou `failureReason` em pagamento pago:

```typescript
type Payment = {
  status: "pending" | "paid" | "failed";
  paidAt?: Date;
  failureReason?: string;
};
```

Correto — cada estado carrega exatamente os dados que possui:

```typescript
type Payment =
  | { status: "pending" }
  | { status: "paid"; paidAt: Date }
  | { status: "failed"; failureReason: string };
```

Branded type, quando trocar identificadores for um risco real:

```typescript
type UserId = string & { readonly __brand: "UserId" };
type OrderId = string & { readonly __brand: "OrderId" };

function toUserId(value: string): UserId {
  if (value.trim() === "") {
    throw new Error("UserId vazio.");
  }

  // Cast único e justificado: o valor acabou de ser validado nesta fronteira.
  return value as UserId;
}
```

