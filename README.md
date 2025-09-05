# snapt

# initial install
luarocks build --only-deps --local --lua-version=5.1

# running busted
luarocks test --local
busted -Xhelper update-snapshots

# TODO
- [ ] should we have a wrapper on top of busted for `-Xhelper` stuff???


