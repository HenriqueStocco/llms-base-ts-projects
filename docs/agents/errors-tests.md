# Erros e testes

Detalhe das seções 11 e 12 de `AGENTS.md`, com exemplos e procedimentos. Não contradiz o núcleo; em caso de divergência, vale o núcleo. A numeração original foi mantida.

## 11. Tratamento de erros e validações

- Validar entradas externas na fronteira apropriada (5.1). Depois de validado, confiar no tipo; não revalidar o mesmo dado em cada camada sem propósito.
- Distinguir, quando a distinção for útil ao consumidor: erro esperado (entrada inválida, recurso inexistente), erro de domínio (regra violada), erro de infraestrutura (dependência indisponível) e falha inesperada (defeito).
- Proibido `catch` vazio e tratamento silencioso.
- Preservar contexto ao propagar: mensagem com o que estava sendo feito e a causa original.
- Não converter falha em resultado de sucesso falso.
- Não usar fallback ou valor padrão que esconda inconsistência de dados.
- Escrever mensagens úteis para quem as recebe, sem expor detalhes internos, segredos ou dados sensíveis.
- Não confundir validação de formato com autorização ou regra de negócio.
- Usar a biblioteca de schemas já adotada no projeto, quando apropriada. Não introduzir uma segunda.
- Tratar datas, fusos, números, moeda, identificadores e formatos de forma consistente com os contratos existentes.
- A estratégia é proporcional: não exigir hierarquia de classes de erro em todo projeto.

Incorreto — a falha desaparece e o chamador recebe um "sucesso" indistinguível de perfil inexistente:

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

Correto — a falha é propagada com contexto e causa preservados:

```typescript
type Profile = { id: string; name: string };

async function loadProfile(id: string, fetchProfile: (id: string) => Promise<Profile>): Promise<Profile> {
  try {
    return await fetchProfile(id);
  } catch (error) {
    throw new Error(`Falha ao carregar o perfil ${id}.`, { cause: error });
  }
}
```

Erro esperado como parte do contrato — o chamador é obrigado a tratar cada caso:

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

Exceção e resultado tipado são ambos válidos. Seguir o estilo predominante do projeto e não misturar os dois no mesmo módulo sem motivo.

## 12. Estratégia de testes

### 12.1 Seleção por risco e fronteira

| Tipo | Usar para |
| --- | --- |
| Unitário | Regras de negócio, transformações, invariantes, casos extremos. |
| Integração | Interação real entre módulos, persistência e dependências relevantes. |
| Contrato | Compatibilidade entre produtores, consumidores e formatos. |
| E2E | Fluxos críticos completos e comportamento observável. |
| Regressão | Reprodução de defeito corrigido. |
| Propriedades / mutação | Quando o benefício for proporcional (parsers, cálculos, invariantes amplos). |

Não exigir todos os tipos em toda alteração. Escolher o nível mais baixo que realmente exercita o risco.

### 12.2 Cenários a avaliar

Conforme a funcionalidade:

- Caminhos válidos.
- Entradas ausentes, malformadas ou inválidas.
- Valores-limite e coleções vazias.
- Estados inválidos e transições não permitidas.
- Falha de dependência, timeout e indisponibilidade.
- Autenticação e autorização, incluindo acesso a recurso de outro usuário ou organização.
- Concorrência, duplicidade e repetição de requisições.
- Atomicidade, rollback e efeitos colaterais.
- Compatibilidade e regressões.
- Falhas parciais e recuperação.

### 12.3 Qualidade

- Testar resultados observáveis e invariantes, não detalhes internos.
- Não escrever teste que apenas espelha a implementação atual sem verificar o contrato.
- Não usar mock para substituir justamente a interação que o teste deveria validar.
- Evitar mocks em excesso e testes frágeis, acoplados à estrutura interna.
- Cobertura de linhas não é indicador suficiente de qualidade.
- Preferir testes determinísticos: controlar relógio, aleatoriedade, ordem e rede.
- Criar teste de regressão para defeito relevante corrigido. Quando viável, confirmar que ele falha sem a correção.

Proibido:

- Remover assertions, enfraquecer ou desativar testes para obter aprovação.
- Alterar a expectativa de um teste apenas porque a implementação falhou. Mudar a expectativa exige que o contrato tenha mudado de fato.
- Declarar testes aprovados sem tê-los executado.

Se o ambiente impedir a execução de algum teste, reportar a limitação e o que ficou sem verificação.

Exemplo — limites e cenários negativos de `parseQuantity` (seção 11). `describe`, `it` e `expect` vêm do runner de testes do projeto:

```typescript
describe("parseQuantity", () => {
  it("aceita os dois limites do intervalo", () => {
    expect(parseQuantity("1")).toEqual({ ok: true, value: 1 });
    expect(parseQuantity("100")).toEqual({ ok: true, value: 100 });
  });

  it("rejeita valores imediatamente fora do intervalo", () => {
    expect(parseQuantity("0")).toEqual({ ok: false, error: "out-of-range" });
    expect(parseQuantity("101")).toEqual({ ok: false, error: "out-of-range" });
  });

  it("rejeita entrada vazia ou composta apenas de espaços", () => {
    expect(parseQuantity("")).toEqual({ ok: false, error: "empty" });
    expect(parseQuantity("   ")).toEqual({ ok: false, error: "empty" });
  });

  it("rejeita o que não é inteiro sem sinal", () => {
    expect(parseQuantity("1.5")).toEqual({ ok: false, error: "not-an-integer" });
    expect(parseQuantity("-1")).toEqual({ ok: false, error: "not-an-integer" });
    expect(parseQuantity("1e2")).toEqual({ ok: false, error: "not-an-integer" });
    expect(parseQuantity("dez")).toEqual({ ok: false, error: "not-an-integer" });
  });
});
```

