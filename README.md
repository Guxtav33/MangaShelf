# 📚 MangaShelf

**MangaShelf** é um leitor de mangás offline desenvolvido em **Flutter**, criado para organizar e ler arquivos de mangá armazenados localmente de forma simples e confortável.

O projeto nasceu da ideia de ter uma biblioteca pessoal semelhante aos antigos leitores de mangá offline: você importa seus próprios arquivos, o MangaShelf organiza os volumes e mantém seu progresso de leitura.

> **Versão atual:** v1.0.0

---

## ✨ Funcionalidades

- 📚 Biblioteca local de mangás
- 📖 Leitor vertical contínuo
- 📦 Importação de arquivos **EPUB, CBZ e ZIP**
- 🗂️ Agrupamento automático de volumes pertencentes à mesma série
- 🖼️ Extração e exibição automática das capas
- 🔢 Organização dos volumes por número
- ↕️ Alternância entre ordem crescente e decrescente
- 🔎 Pesquisa na biblioteca
- 💾 Persistência da biblioteca após fechar ou atualizar o aplicativo
- 📍 Salvamento do progresso de leitura
- ▶️ Opção de continuar a leitura
- 📊 Indicador de progresso da série
- 🌙 Tema escuro
- ☀️ Tema claro
- 🔍 Zoom durante a leitura
- 🖱️ Zoom por interação no desktop
- 🤏 Suporte a gestos de zoom em dispositivos móveis
- 📱 Interface responsiva para desktop e dispositivos móveis
- 🗑️ Remoção de volumes da biblioteca
- 📑 Exibição individual dos volumes dentro de cada série

---

## 🖥️ Interface

A biblioteca do MangaShelf organiza os arquivos importados por série.

Ao selecionar uma obra, o usuário pode visualizar:

- capa da série;
- autor;
- quantidade de volumes;
- progresso de leitura;
- volumes disponíveis;
- volumes já lidos;
- último volume acessado.

O leitor utiliza uma interface focada no conteúdo, exibindo as páginas verticalmente e mantendo o progresso da leitura automaticamente.

---

## 📁 Formatos suportados

Atualmente o MangaShelf possui suporte para:

| Formato | Suporte |
|---|---|
| EPUB | ✅ |
| CBZ | ✅ |
| ZIP | ✅ |

Os arquivos são processados localmente pelo aplicativo.

---

## 🛠️ Tecnologias

O MangaShelf foi desenvolvido principalmente utilizando:

- **Flutter**
- **Dart**
- Material Design
- armazenamento local
- processamento local de arquivos EPUB/CBZ/ZIP

O projeto possui estrutura Flutter para:

- Windows
- Web
- Android
- iOS
- Linux
- macOS

> A disponibilidade de todos os recursos pode variar de acordo com a plataforma.

---

## 🚀 Executando o projeto

### Requisitos

Tenha o Flutter instalado e configurado.

Verifique a instalação:

```bash
flutter doctor