# orca-lc config reads keys from .orca/config.json
r=$(new_repo '{"project":"demo","gate":"true"}')
assert_eq "$(cd "$r" && orca-lc config project)" demo
assert_eq "$(cd "$r" && orca-lc config missing)" ""
