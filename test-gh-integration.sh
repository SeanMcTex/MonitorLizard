#!/bin/bash
# Test GitHub CLI integration for MonitorLizard

echo "🦎 MonitorLizard - GitHub CLI Integration Test"
echo "=============================================="
echo ""

# Check if gh is installed
echo "1. Checking if gh CLI is installed..."
if command -v gh &> /dev/null; then
    echo "   ✅ gh CLI is installed"
    gh --version
else
    echo "   ❌ gh CLI is not installed"
    echo "   Install with: brew install gh"
    exit 1
fi
echo ""

# Check if gh is authenticated
echo "2. Checking gh authentication status..."
if gh auth status &> /dev/null; then
    echo "   ✅ gh CLI is authenticated"
    gh auth status
else
    echo "   ❌ gh CLI is not authenticated"
    echo "   Authenticate with: gh auth login"
    exit 1
fi
echo ""

# Test fetching open PRs
echo "3. Testing PR search (your open PRs)..."
echo "   Command: gh search prs --author=@me --state=open --json number,title,repository --limit 5"
echo ""

PRS=$(gh search prs --author=@me --state=open --json number,title,repository,url,author,updatedAt --limit 5 2>&1)

if [ $? -eq 0 ]; then
    echo "   ✅ Successfully fetched PRs"
    echo "$PRS" | jq '.' 2>/dev/null || echo "$PRS"

    # Count PRs
    PR_COUNT=$(echo "$PRS" | jq '. | length' 2>/dev/null || echo "0")
    echo ""
    echo "   Found $PR_COUNT open PR(s)"

    # Test fetching status for first PR if available
    if [ "$PR_COUNT" -gt 0 ]; then
        echo ""
        echo "4. Testing PR status fetch for first PR..."

        PR_NUMBER=$(echo "$PRS" | jq -r '.[0].number' 2>/dev/null)
        REPO=$(echo "$PRS" | jq -r '.[0].repository.nameWithOwner' 2>/dev/null)

        if [ -n "$PR_NUMBER" ] && [ -n "$REPO" ]; then
            echo "   PR: #$PR_NUMBER in $REPO"
            echo "   Command: gh pr view $PR_NUMBER --repo $REPO --json statusCheckRollup"
            echo ""

            STATUS=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json headRefName,statusCheckRollup 2>&1)

            if [ $? -eq 0 ]; then
                echo "   ✅ Successfully fetched PR status"
                echo "$STATUS" | jq '.' 2>/dev/null || echo "$STATUS"
            else
                echo "   ⚠️  Could not fetch PR status"
                echo "   $STATUS"
            fi
        fi
    else
        echo ""
        echo "4. No open PRs found to test status fetch"
        echo "   Create a PR to test full functionality"
    fi
else
    echo "   ❌ Failed to fetch PRs"
    echo "   $PRS"
    exit 1
fi

echo ""
echo "=============================================="
echo "✅ All GitHub CLI integration tests passed!"
echo ""
echo "You're ready to build and run MonitorLizard."
echo "See README.md for build instructions."
