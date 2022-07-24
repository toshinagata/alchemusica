#!/bin/sh
REV=$1
echo "Git hash for revision $REV:"
git rev-list --reverse HEAD | nl | awk "{ if (\$1 + 10 == $REV) { print \$2 } }"
