# Arquitetura, nomes, formatação e comentários

Detalhe das seções 7 a 10 de `AGENTS.md`, com exemplos e procedimentos. Não contradiz o núcleo; em caso de divergência, vale o núcleo. A numeração original foi mantida.

## 7. Arquitetura e organização de responsabilidades

Critérios, não uma estrutura obrigatória.

- Organizar módulos por responsabilidade ou domínio, conforme o contexto do projeto.
- Manter fronteiras de dependência claras e sem ciclos.
- Evitar módulos que concentrem responsabilidades sem relação.
- Extrair código compartilhado somente com benefício real e uso concreto.
- Não criar camadas, interfaces, factories, repositories ou services automaticamente.
- Não impor Clean Architecture, DDD, MVC, CQRS ou outro padrão. Adotá-los quando a complexidade e os requisitos justificarem, ou quando o projeto já os utilizar de forma coerente.
- Não colocar regra de negócio em local inadequado (handler, componente de UI, consulta) apenas para reduzir a quantidade de arquivos.
- Reconhecer quando um módulo precisa crescer, ser dividido ou reorganizado: múltiplos motivos independentes de mudança, testes que exigem preparar contexto sem relação, alterações que tocam sempre os mesmos pontos distantes.
- Considerar o custo de mudança: preferir estruturas que tornem a próxima alteração provável local e barata.

Separação proporcional — regra pura isolada do I/O, sem camadas adicionais:

```typescript
type Order = { id: string; totalCents: number };

type OrderStore = {
  findById(id: string): Promise<Order | undefined>;
  save(order: Order): Promise<void>;
};

// Regra de negócio: sem I/O, testável sem infraestrutura.
export function applyDiscount(totalCents: number, percent: number): number {
  if (percent < 0 || percent > 100) {
    throw new RangeError("O desconto deve estar entre 0 e 100.");
  }

  return Math.round(totalCents * (1 - percent / 100));
}

// Orquestração: os efeitos colaterais ficam explícitos e na fronteira.
export async function applyCoupon(orderId: string, percent: number, orders: OrderStore): Promise<Order> {
  const order = await orders.findById(orderId);

  if (!order) {
    throw new Error(`Pedido ${orderId} não encontrado.`);
  }

  const updated = { ...order, totalCents: applyDiscount(order.totalCents, percent) };

  await orders.save(updated);

  return updated;
}
```

### 7.1 Monorepos

Sem presumir ferramenta de workspace ou de orquestração.

- Separar aplicações (unidades implantáveis) de pacotes (código reutilizável). Aplicações não importam umas das outras.
- Cada pacote expõe uma API pública explícita. Não importar caminhos internos de outro pacote.
- Declarar as dependências de cada pacote no próprio manifesto. Não depender de pacotes disponíveis por acidente na raiz.
- Manter o grafo de dependências acíclico e em uma direção: aplicações dependem de pacotes, nunca o inverso.
- Compartilhar schemas, tipos e lógica de domínio quando houver mais de um consumidor real e um único dono do contrato. Um contrato compartilhado é uma API: alterá-lo afeta todos os consumidores.
- Não criar pacote compartilhado artificial nem pacotes genéricos que acoplam aplicações sem relação.
- Executar build, testes e verificações do pacote alterado **e** dos pacotes que dependem dele, quando o projeto permitir.
- Preservar o isolamento: configuração, segredos e código específico de runtime de uma aplicação não vazam para pacotes compartilhados.

## 8. Nomenclatura e organização de arquivos

### 8.1 Nomes

Padrão geral, subordinado às convenções existentes do projeto e às exigências do framework em uso:

- `kebab-case` para arquivos e diretórios.
- `camelCase` para variáveis e funções.
- `PascalCase` para classes, tipos e interfaces.
- Nomes que expressem a responsabilidade. Evitar abreviações obscuras e nomes genéricos (`data`, `info`, `manager`, `handler2`).
- Extensões e convenções coerentes com o restante do projeto.

### 8.2 Sem redundância contextual

Quando o diretório já estabelece o domínio, não repetir o domínio no nome do arquivo.

Preferir:

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

Evitar como padrão:

```text
users/
├── users.service.ts
├── users.repository.ts
├── users.schema.ts
└── users.types.ts
```

A árvore acima ilustra a nomenclatura, não um conjunto obrigatório de arquivos (8.4).

### 8.3 Testes

- Preferir um diretório `tests/` dentro do módulo, agrupando os testes daquele módulo.
- Nomear cada teste pelo módulo, função ou comportamento testado.
- Manter fixtures e helpers próximos dos testes que os usam. Compartilhar somente com reutilização concreta.
- Verificar a configuração de descoberta de testes antes de criar, mover ou renomear arquivos de teste.
- Respeitar a convenção existente quando for funcional e consistente. Não migrar a organização de testes sem pedido.

### 8.4 Sem proliferação de arquivos

Não criar automaticamente:

- `types.ts` em todo diretório.
- `constants.ts` para uma única constante.
- `utils.ts`, `helpers.ts` ou `common.ts` como depósito de funções sem relação.
- `index.ts` em todo módulo, sem necessidade de API pública explícita.
- Um arquivo por função ou declaração.
- Camadas e arquivos vazios para cumprir uma estrutura teórica.

Separar arquivos por coesão, responsabilidade, testabilidade, legibilidade ou limite de dependência — nunca por hábito.

## 9. Formatação e legibilidade visual

Legibilidade é prioridade explícita. Não comprimir código para reduzir linhas; não fragmentá-lo com espaçamento excessivo.

- Seguir o formatador configurado no projeto. Não reformatar código fora do escopo.
- Manter juntas, uma por linha e sem linha em branco entre elas, as declarações diretamente relacionadas.
- Usar uma linha em branco entre blocos lógicos distintos: declarações, condicionais, loops, funções e operações que representam etapas diferentes.
- Não colocar um `if` independente colado à declaração anterior quando forem etapas distintas.
- Não comprimir função, condicional, retorno ou declarações diferentes em uma única linha.
- Usar múltiplas linhas para objetos, arrays, chamadas e condições complexas quando facilitar a leitura.
- Não inserir linhas em branco dentro de uma mesma operação coesa.
- Preferir retorno antecipado quando reduzir aninhamento.

Incorreto:

```typescript
type User = { id: string; name: string; active: boolean };

function listActiveUsers(users: readonly User[]) {
  const activeUsers = users.filter((user) => user.active);
  if (activeUsers.length === 0) return [];
  return activeUsers.map((user) => ({ id: user.id, name: user.name }));
}
```

Correto:

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

Formatadores automáticos não impõem todas essas regras de espaçamento entre declarações. Usar a configuração automática para o que ela cobre e a revisão do diff para o restante.

## 10. Comentários e documentação

- Escrever comentários curtos, diretos e úteis.
- Comentar intenção, restrições, decisões não óbvias, invariantes e efeitos colaterais.
- Não comentar o óbvio nem repetir em palavras o que o código já expressa.
- Atualizar ou remover comentários que a alteração tornou incorretos.
- Não deixar código comentado nem marcadores de pendência sem contexto.
- Documentar APIs públicas, contratos e comportamentos relevantes quando necessário. Não criar documentação extensa para funções triviais.
- Registrar decisões arquiteturais significativas em ADR quando o contexto justificar e o projeto adotar a prática.
- Não criar documentação que duplique o código ou as instruções centrais.

