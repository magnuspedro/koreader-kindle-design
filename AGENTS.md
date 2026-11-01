# AGENTS.md — contexto para agentes

Este repositório guarda os **patches Lua** que dão ao KOReader de um **Kindle Basic 2024** uma interface simples,
no estilo do Kindle. Leia este arquivo inteiro antes de mudar qualquer coisa.

## Alvo

| | |
|---|---|
| Aparelho | Kindle Basic 2024, tela 1072×1448, 300 dpi, e-ink em tons de cinza |
| KOReader | 2026.07.1 (código-fonte: tag `v2026.07.1` em github.com/koreader/koreader) |
| Conexão | só MTP pelo cabo USB (sem SSH; o plugin SSH está desativado) |
| Livros | EPUB (crengine). PDFs devem continuar com a interface nativa |
| Idioma | o dono fala português (Brasil). Textos da interface em **português**; código e comentários em inglês |

## Preferências do dono (obrigatório)

1. **Prioridades: funcionalidade, minimalismo e rapidez.** Nada de enfeite que custe tempo de tela ou refresh de e-ink.
2. **Sempre testar no emulador Docker antes** (veja "Fluxo de trabalho").
3. **Mostrar prévia e esperar aprovação** antes de copiar para o Kindle ou dar `git push`.
   Gere screenshot em tons de cinza com moldura, abra para ele (`open arquivo.png`) e pergunte.
4. Ao pedir escolha de design, mostre **opções lado a lado testadas no emulador**.
5. O SimpleUI que ele teve antes **nunca foi configurado**: não use as configurações dele como referência.
6. Respostas ao dono: curtas, em português, sem jargão.

## Estrutura

```
patches/                     -> vão em koreader/patches/ no Kindle
  2-kindle-header.lua        barra do topo na leitura
  2-kindle-ui.lua            barra de ferramentas, painel "Aa", Índice
  2-kindle-home.lua          tela inicial (sobre o FileManager)
  2-kindle-menu.lua          visual do menu do KOReader (TouchMenu)
settings/
  design-settings.lua        snapshot das configs de visual do Kindle (referência, sem dados pessoais)
  gestures.lua               gestures do dono (vai em koreader/settings/)
docs/screenshots/, docs/gestures/   imagens do README (geradas no emulador)
tools/kmtp.c                 cliente MTP de sessão única (binário kmtp fica fora do git)
tools/emu/                   emulador do KOReader em Docker
tools/gen_gestures.py        gera docs/gestures/*.svg
fonts/                       só README: os .ttf não são redistribuídos (licença da Legible Next)
mockups/                     esboços antigos
```

## O que cada patch faz

### 2-kindle-header.lua — barra do topo
- Texto: `tempo restante no capítulo · hora · % lido` (FONT_SIZE 16, BAR_H 26).
- Reserva espaço: substitui a margem superior do livro (`ReaderTypeset.onSetPageMargins`).
- Desliga a barra de status do crengine (`copt_status_line = 1`), senão ela desenha por baixo.
- Redesenha a orelha de marcador (`view.dogear`) por cima da barra.
- Segurar a barra → `ShowConfigMenu` (painel Aa). Relógio atualiza a cada minuto só na região da barra.

### 2-kindle-ui.lua — leitura
- **Toque no topo / deslizar ↓ do topo** → barra de ferramentas: Biblioteca · Índice · Fonte · Buscar · Marcar · Menu
  (`ReaderMenu.onTapShowMenu` / `onSwipeShowMenu`).
- **`ReaderConfig.onShowConfigMenu`** → painel "Aa" próprio (abas Temas · Fonte · Layout · Mais). O painel nativo
  continua em "Mais › Todas as opções do KOReader" (`ReaderConfig:showNativePanel`).
- Mudanças no painel: evento `ConfigChange` + evento da opção, e salvam `copt_*` / `cre_font` globais
  (viram padrão para livros novos, como no Kindle). Notificações silenciadas com `Notification:setNotifySource`.
- Temas aplicam várias opções dentro de `BatchedUpdate`/`BatchedUpdateDone` (um re-render só).
- **`ReaderToc.onShowToc`** → Índice simples em tela cheia (vale para gestures, botão e menu).
- **Toque embaixo (zona 5, painel Aa):** só uma faixa fina, metade da altura do KOReader (`AA_TAP_SCALE = 0.5`,
  presa na borda de baixo), sem a parte mais alta no meio (`readerconfigmenu_ext_tap` = mesma faixa): o dono é
  canhoto e vira página tocando embaixo, no meio. Re-registra as duas zonas depois de
  `ReaderConfig.initGesListener`. O deslizar ↑ a partir de baixo não muda. Diagrama em `tools/gen_gestures.py`.
- Só age em documentos crengine (`isCre`); PDF usa a interface nativa.

### 2-kindle-home.lua — tela inicial
- Widget em tela cheia mostrado por cima do `FileManager` (hook em `FileManager.init`; o ícone de casa do
  navegador volta para ela via `FileManager.onHome`; fecha em `onShowingReader`).
- Abas: Início · Biblioteca (grade 3×2 com filtros) · Arquivos (navegador nativo) · Menu.
- Estilos (`kindle_home_style`; **segurar o título "Início"** abre o seletor):
  `estante_relogio` (**padrão aprovado**), `minimal`, `minimal_estante`, `painel`, `dados`, `estante`,
  `inicio`, `grade`, `lista`. Os estilos são listas de módulos em `PRESETS`; módulos em `M.*`
  (relógio, lendo agora, também lendo, estante, citação, meta, estatísticas, mapa de atividade, ações rápidas).
- **Rapidez:** estilos em `HISTORY_ONLY` leem só o `ReadHistory` (`Library.recent`). A varredura da pasta
  (`Library.scan`) só acontece na aba Biblioteca. Tempo restante (`Library.timeLeft`) só é calculado para
  quem mostra. A citação do dia é calculada uma vez por dia.
- Dados: capas/títulos do cache do CoverBrowser (`bookinfomanager`), progresso via `BookList`,
  estatísticas no SQLite `settings/statistics.sqlite3` (`lua-ljsqlite3`), destaques via `DocSettings`.

### 2-kindle-menu.lua — menu do KOReader
- Só visual: abas com nome em português e sublinhado, separadores claros, "›" em submenus (remove o "▸"
  do texto), rodapé "‹ Voltar".
- `TouchMenuBar` e `TouchMenuItem` são `local` em `touchmenu.lua`: o patch os alcança com
  `debug.getupvalue(TouchMenu.init / TouchMenu.updateItems)` e não faz nada se não achar.
- **Rapidez:** o visual (separadores, rodapé) entra no primeiro `updateItems`, então o menu é montado uma vez só
  ao abrir. As listas do menu do navegador são montadas 2 s depois dele abrir (`setUpdateItemTable`),
  para o primeiro toque em "Menu" ser rápido.
- **Sem piscar:** `NO_FLASH = true` abre e fecha o menu com refresh `"ui"` só na área do menu (o KOReader
  piscava ao abrir e piscava a tela inteira ao fechar). Se aparecer fantasma no e-ink, troque para `false`.

## Fluxo de trabalho

1. **Código-fonte de referência:** clone `koreader` na tag `v2026.07.1` (pasta temporária) e leia a API antes de usar.
2. **Checar sintaxe:** `luajit -b patches/ARQUIVO.lua /dev/null`.
3. **Emulador** (`tools/emu/README.md`): build Linux arm64 do KOReader em Docker + Xvfb, tela 1072×1448 @ 300 dpi.
   - `./t.sh nome tap X Y wait 1 swipe X1 Y1 X2 Y2 hold X Y` → screenshot em `work/shots/nome.png`.
   - Depois de trocar patches: `docker restart koemu` (ou `restart.sh`) e esperar ~20 s.
   - `KOARG=/work/books/x.epub` abre um livro direto; sem ele, abre o FileManager (tela inicial).
   - Livros de teste: domínio público do Projeto Gutenberg (ex.: Dom Casmurro, id 55752).
   - Dados de exemplo para a tela inicial: sidecars `livro.sdr/metadata.epub.lua` com `percent_finished`,
     `doc_pages`, `partial_md5_checksum`, `summary.status`, `annotations`; `history.lua`; linhas em `book` e
     `page_stat_data` do `statistics.sqlite3`. Diga ao dono quando as imagens usam dados de exemplo.
   - Veja o `work/ko.log` procurando `traceback` depois de cada teste.
4. **Prévia:** `magick X.png -colorspace Gray -resize 50% -bordercolor "#cfcfcf" -border 1 -bordercolor "#1e1e1e" -border 22 -bordercolor white -border 6 Y.png`; compare lado a lado com `magick montage` (use `-font "/System/Library/Fonts/Supplemental/Arial Bold.ttf"` para rótulos).
5. **Aprovação do dono.**
6. **Instalar no Kindle** com `tools/kmtp` (abaixo) e conferir os tamanhos com `wc -c`.
7. **Atualizar README** (imagens em `docs/screenshots/`), commit e `git push`.

## Kindle por MTP (macOS)

- O Kindle **cai do USB a cada sessão libmtp fechada**; IDs de objeto mudam entre sessões. Nunca apague por ID.
- Use `tools/kmtp` (uma sessão, comandos por linha, separados por TAB): `ls`, `tree`, `get <caminho> <local>`,
  `rm <caminho>` (só arquivos), `put <local> <pasta>` (falha se existe: `rm` antes), `quit`.
- Compilar: `cc -O2 -o tools/kmtp tools/kmtp.c $(pkg-config --cflags --libs libmtp)` (`brew install libmtp`).
- Antes de cada sessão, espere `ioreg -p IOUSB | grep Kindle`. Depois dela, o aparelho some até reconectar.
- Exemplo: `printf 'rm\tkoreader/patches/2-kindle-ui.lua\nput\t%s/patches/2-kindle-ui.lua\tkoreader/patches\nquit\n' "$PWD" | tools/kmtp`
- **Configurações (`settings.reader.lua`):** o KOReader regrava ao fechar. Só edite com o KOReader **fechado**
  (peça ao dono) ou peça para ele mudar pelo menu.

## Armadilhas já encontradas

- Patches só rodam se o nome começar com `0-`, `1-`, `2-`, `8-` ou `9-`. **`3-` a `7-` são reservados e ignorados em silêncio.**
- Plugins (ex.: `bookinfomanager` do CoverBrowser) **não estão no `package.path`** quando os patches rodam:
  faça `require` na hora do uso.
- `VerticalGroup`/`HorizontalGroup`: se chamar `getSize()` e depois inserir itens, chame `resetLayout()`.
- `FrameContainer` ignora `width`/`height` no `getSize()`: para caixa de tamanho fixo use `OverlapGroup{dimen=...}`
  ou `CenterContainer{dimen=...}`.
- `UIManager:show(widget)` sem tipo de refresh pode não atualizar a tela: passe `"flashui"`/`"ui"` e a região.
- `string.upper` do Lua não converte acentos (`ç`, `ã`…): use a tabela `UPPER` do `2-kindle-home.lua`.
- `getMenuText` envolve "▸" com marcadores de direção (`BD.ltr`): compare com o sufixo exato.
- `conn:rowexec` do ljsqlite3 dá erro se vierem várias linhas: use `LIMIT 1`.
- No emulador, um toque logo após re-render pode ser perdido (adicione `wait 1`). Toques "de limpeza"
  podem abrir livros se o aviso não aparecer mais: confira onde vai tocar.
- A tela inicial é uma janela separada. O KOReader só fecha quando não sobra janela: por isso
  `FileManager.onClose` ("Sair") fecha a tela inicial antes. Sem isso o Kindle parece travado ao sair.
- Cores: use tons de cinza (`Blitbuffer.COLOR_*`). O emulador é colorido; o aparelho não.
- Não deixe o refresh de e-ink pesado: atualize só regiões (`setDirty(widget, "ui", geom)`).

## Licenças

- Repositório: AGPL-3.0 (mesma do KOReader, porque os patches usam a API interna dele).
- Fontes NV (ebook-fonts, Nico Verbruggen) não são redistribuídas.
- Imagens geradas com livros de domínio público.

## Commits

- Mensagens em inglês, no imperativo, com corpo curto explicando o porquê.
- Repositório público: nada de e-mail, número de série do Kindle, caminhos pessoais ou dados de leitura reais.
