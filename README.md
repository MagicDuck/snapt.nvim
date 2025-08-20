# snapt

# initial install
luarocks build --only-deps --local --lua-version=5.1

# running busted
luarocks test --local
busted -Xhelper update-snapshots


