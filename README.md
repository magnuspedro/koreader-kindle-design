# KOReader com cara de Kindle

Patches para o [KOReader](https://github.com/koreader/koreader) que trocam a interface de leitura de EPUB
por uma mais simples, parecida com a do Kindle: barra no topo, barra de ferramentas,
painel **Aa** com abas e um **Índice** limpo. Feito e testado num Kindle Basic 2024 com KOReader 2026.07.1.

![Leitura, barra de ferramentas, painel Aa e Índice](docs/screenshots/hero.png)

## O que muda

| | Antes (KOReader) | Agora |
|---|---|---|
| Topo da página | barra do crengine com título, bateria, marcas de capítulo | **tempo restante no capítulo · hora · % lido** |
| Toque no topo | menu completo do KOReader + painel inferior | **barra de ferramentas**: Biblioteca · Índice · Fonte · Buscar · Marcar · Menu |
| Toque embaixo | painel com 6 ícones e dezenas de opções | **painel Aa**: Temas · Fonte · Layout · Mais |
| Índice | lista do KOReader | **tela cheia**, capítulo atual em destaque, toque para ir |

Os menus completos do KOReader continuam a um toque: botão **Menu** na barra de ferramentas e
**Mais › Todas as opções do KOReader** no painel Aa. PDFs continuam com a interface padrão.

## Painel Aa

![Abas Temas, Fonte, Layout e Mais](docs/screenshots/painel-aa.png)

- **Temas**: Compacto, Padrão, Grande e "Meu tema" (salva fonte, tamanho, entrelinha, margens e espessura).
- **Fonte**: lista com cada fonte escrita nela mesma, tamanho (− régua +) e espessura do traço.
- **Layout**: orientação, espaçamento entre linhas, margens e alinhamento (à esquerda / justificado).
- **Mais**: modo de renderização (Livro / Web / Plano), espaço entre palavras e contraste.

As mudanças aparecem na hora, com o painel aberto, e viram o padrão para livros abertos pela primeira vez,
como no Kindle.

<p align="center">
  <img src="docs/screenshots/fonts.png" width="32%" alt="Lista de fontes">
  <img src="docs/screenshots/toolbar.png" width="32%" alt="Barra de ferramentas">
  <img src="docs/screenshots/read.png" width="32%" alt="Página de leitura">
</p>

## Gestos

| Gesto | Ação |
|---|---|
| Toque no topo / deslizar para baixo a partir do topo | barra de ferramentas |
| Toque embaixo | painel Aa |
| Segurar a barra do topo | painel Aa |
| Toque fora do painel / deslizar o painel para baixo | fecha |
| Deslizar para os lados no Índice ou na lista de fontes | troca de página |

## Instalação

1. Copie os arquivos de `patches/` para `koreader/patches/` no Kindle.
2. (Opcional) Instale as fontes indicadas em [`fonts/README.md`](fonts/README.md) em `koreader/fonts/`.
3. Reinicie o KOReader. Patches só são carregados quando ele abre.

Para desfazer, apague os patches e reinicie.

> O nome do patch precisa começar com `2-`. O KOReader reserva os prefixos `3-` a `7-` e **não executa** esses arquivos.

## Conteúdo do repositório

| Caminho | O que é |
|---|---|
| `patches/2-kindle-header.lua` | barra do topo (reserva espaço na margem, relógio atualiza a cada minuto) |
| `patches/2-kindle-ui.lua` | barra de ferramentas, painel Aa e Índice |
| `settings/design-settings.lua` | minhas configurações de visual (fonte, margens, rodapé, protetor de tela) para referência |
| `fonts/` | quais fontes uso e onde baixar |
| `mockups/` | esboços feitos antes da implementação |
| `tools/kmtp.c` | cliente MTP de sessão única para o Kindle no macOS (o Kindle desconecta após cada sessão do libmtp) |
| `tools/emu/` | emulador do KOReader em Docker com a tela do Kindle (1072×1448, 300 dpi), usado para gerar as imagens |

### kmtp (macOS)

```sh
brew install libmtp
cc -O2 -o tools/kmtp tools/kmtp.c $(pkg-config --cflags --libs libmtp)
printf 'ls\tkoreader/patches\nquit\n' | tools/kmtp
```

Comandos separados por TAB: `ls`, `tree`, `get <caminho> <local>`, `rm <caminho>`, `put <local> <pasta>` (falha se já existe), `quit`.

## Créditos e licença

- [KOReader](https://github.com/koreader/koreader) (AGPL-3.0). Os patches usam a API interna dele.
- Imagens geradas no emulador com *Dom Casmurro*, de Machado de Assis (domínio público, [Projeto Gutenberg](https://www.gutenberg.org/ebooks/55752)).
- Licença: [AGPL-3.0](LICENSE), a mesma do KOReader.
