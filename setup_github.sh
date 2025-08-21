#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REPO="${REPO:-aurora-social}"          # Pode ser só o nome; o script completa com o owner logado
DIR="${DIR:-.}"
VISIBILITY="${VISIBILITY:-public}"     # public | private | internal (orgs)
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# --- Helpers ---
have() { command -v "$1" >/dev/null 2>&1; }

echo "🔎 Checking dependencies..."
have git || { echo "❌ git not found. Install git and retry."; exit 1; }
have gh  || { echo "❌ GitHub CLI (gh) not found. Install from https://cli.github.com/ and retry."; exit 1; }

echo "🔐 Checking GitHub auth..."
if ! gh auth status >/dev/null 2>&1; then
  echo "You are not logged in with gh. Opening browser to authenticate..."
  gh auth login -w -s 'repo,read:org,project'
fi

# --- Normalize REPO owner (usa usuário logado no gh se faltar owner) ---
if [[ "$REPO" != */* ]]; then
  OWNER="$(gh api user -q .login 2>/dev/null || echo '')"
  [ -z "$OWNER" ] && { echo "❌ Could not resolve GitHub owner. Provide REPO as OWNER/REPO."; exit 1; }
  REPO="$OWNER/$REPO"
fi

# --- Ensure directory exists ---
if [ ! -d "$DIR" ]; then
  echo "❌ Project directory '$DIR' not found. Create it or set DIR=/path/to/your/project before running."
  exit 1
fi

cd "$DIR"

# --- Git initialization ---
if [ ! -d .git ]; then
  echo "🧰 Initializing git repo..."
  git init
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "chore: initial public release (aurora-social)" || true
fi
git branch -M "$DEFAULT_BRANCH"

# --- Create or connect remote repo ---
echo "🌐 Ensuring remote repository '$REPO' exists..."
if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "✅ Remote repository exists."
  if git remote get-url origin >/dev/null 2>&1; then
    echo "🔁 Remote 'origin' already set to: $(git remote get-url origin)"
  else
    git remote add origin "https://github.com/$REPO.git"
  fi
else
  echo "📦 Creating repository on GitHub..."
  gh repo create "$REPO" --"$VISIBILITY" \
    --description "Cadastro socioeconômico offline-first (React Native + Django), PDF por inscrito e admin — projeto de portfólio." \
    --disable-wiki --disable-issues=false --homepage "" >/dev/null
  git remote add origin "https://github.com/$REPO.git"
fi

echo "⬆️ Pushing '$DEFAULT_BRANCH'..."
git push -u origin "$DEFAULT_BRANCH" || true

# --- .github templates (idempotente) ---
mkdir -p .github/ISSUE_TEMPLATE
if [ ! -f .github/ISSUE_TEMPLATE/bug_report.yml ]; then
  cat > .github/ISSUE_TEMPLATE/bug_report.yml <<'YAML'
name: Bug report
description: Reporte um problema
labels: [bug]
body:
  - type: textarea
    id: what
    attributes: { label: O que aconteceu?, description: Descreva o bug }
    validations: { required: true }
  - type: textarea
    id: steps
    attributes: { label: Passos para reproduzir }
  - type: textarea
    id: expected
    attributes: { label: Comportamento esperado }
YAML
fi

if [ ! -f .github/ISSUE_TEMPLATE/feature_request.yml ]; then
  cat > .github/ISSUE_TEMPLATE/feature_request.yml <<'YAML'
name: Feature request
description: Sugira uma melhoria
labels: [enhancement]
body:
  - type: textarea
    id: value
    attributes: { label: Valor para o usuário, description: Por que é útil? }
    validations: { required: true }
  - type: textarea
    id: scope
    attributes: { label: Escopo, description: O que está dentro/fora? }
YAML
fi

if ! git diff --quiet .github; then
  git add .github
  git commit -m "docs: add issue templates" || true
  git push || true
fi

# --- Labels (idempotente) ---
echo "🏷️ Creating labels (if missing)..."
labels=(
  "bug|#B60205"
  "enhancement|#1D76DB"
  "documentation|#0075CA"
  "good-first-issue|#7057FF"
  "priority:high|#D73A4A"
)

for pair in "${labels[@]}"; do
  name="${pair%%|*}"
  color="${pair##*|}"
  if gh label list -R "$REPO" | grep -qi "^${name}\b"; then
    echo "• $name already exists"
  else
    gh label create "$name" -R "$REPO" -c "$color" -d "" || true
  fi
done

# --- Milestones (POSIX friendly) ---
echo "🎯 Creating milestones (if missing)..."
MILESTONES_LIST=$(cat <<'EOF'
M1-Backend CRUD+PDF|Back-end com CRUD e PDF por inscrito
M2-Mobile Offline|Coleta offline e sincronização
M3-Admin & Filtros|Django Admin + filtros avançados
M4-Hardening & Docs|Segurança, testes e documentação
EOF
)

EXISTING_MS_JSON="$(gh api "repos/${REPO}/milestones" 2>/dev/null || echo '[]')"

while IFS='|' read -r title description; do
  [ -z "${title:-}" ] && continue
  if echo "$EXISTING_MS_JSON" | grep -q "\"title\": \"${title}\""; then
    echo "• Milestone '${title}' already exists"
  else
    gh api -X POST "repos/${REPO}/milestones" \
      -f title="$title" \
      -f state="open" \
      -f description="$description" >/dev/null && \
    echo "• Created milestone '${title}'"
  fi
done <<EOF
$MILESTONES_LIST
EOF

# --- Skip Project creation (CLI atual não dá suporte simples) ---
echo "ℹ️ Skipping automatic Project creation. Create it via GitHub UI if needed."

echo "✅ Done! Repository ready: https://github.com/$REPO
Tip: You can set defaults when running:
  REPO=$(gh api user -q .login)/aurora-social DIR=. ./setup_github.sh
"
