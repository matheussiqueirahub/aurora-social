#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REPO="${REPO:-siqueirahub/aurora-social}"
DIR="${DIR:-app-social}"
VISIBILITY="${VISIBILITY:-public}"  # public | private | internal (orgs)
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
  git commit -m "chore: initial public release (aurora-social)"
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
git push -u origin "$DEFAULT_BRANCH"

# --- Create .github templates if missing ---
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

# Commit templates if newly created
if ! git diff --quiet .github; then
  git add .github
  git commit -m "docs: add issue templates"
  git push
fi

# --- Labels (idempotent) ---
echo "🏷️ Creating labels (if missing)..."
labels=(
  "bug:#B60205"
  "enhancement:#1D76DB"
  "documentation:#0075CA"
  "good-first-issue:#7057FF"
  "priority:high:#D73A4A"
)

for pair in "${labels[@]}"; do
  name="${pair%%:*}"
  color="${pair##*:}"
  if gh label list --repo "$REPO" | grep -q -i "^${name}\b"; then
    echo "• $name already exists"
  else
    gh label create "$name" -R "$REPO" -c "${color}" -d "" || true
  fi
done

# --- Milestones ---
echo "🎯 Creating milestones (if missing)..."
declare -A milestones=(
  ["M1-Backend CRUD+PDF"]="Back-end com CRUD e PDF por inscrito"
  ["M2-Mobile Offline"]="Coleta offline e sincronização"
  ["M3-Admin & Filtros"]="Django Admin + filtros avançados"
  ["M4-Hardening & Docs"]="Segurança, testes e documentação"
)

for title in "${!milestones[@]}"; do
  if gh api "repos/${REPO}/milestones" | grep -q "\"title\": \"${title}\""; then
    echo "• Milestone '${title}' already exists"
  else
    gh api -X POST "repos/${REPO}/milestones" \
      -f title="${title}" \
      -f state="open" \
      -f description="${milestones[$title]}" >/dev/null
    echo "• Created milestone '${title}'"
  fi
done

# --- Optional: create user project (beta) ---
if gh project --help >/dev/null 2>&1; then
  if ! gh project list --owner "${REPO%%/*}" --limit 100 | grep -q "^Aurora Social"; then
    echo "🗂️ Creating user project 'Aurora Social' (kanban)..."
    gh project create "Aurora Social" --owner "${REPO%%/*}" --format=kanban >/dev/null || true
  else
    echo "• Project 'Aurora Social' already exists (skip)"
  fi
fi

echo "✅ Done! Repository ready: https://github.com/$REPO
Tip: You can set defaults when running:
  REPO=siqueirahub/aurora-social DIR=app-social ./setup_github.sh
