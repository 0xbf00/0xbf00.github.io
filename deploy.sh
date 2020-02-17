# Temporarily store uncommited changes
git stash

# Verify correct branch
git checkout develop

# Build new files
cabal run ubrigens clean
cabal run ubrigens build

# Get previous files
git fetch --all
git checkout -b master --track origin/master

# Overwrite existing files with new files
cp -a _site/. .

# Commit
git add -A
git commit -m "Published on $(date +"%d-%m-%Y")."

# Push
git push origin master:master

# Restoration
git checkout develop
git branch -D master
git stash pop