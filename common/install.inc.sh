# Installer utility functions

function INFO() {
  echo -e "\e[37m\e[44m[INFO]\e[0m $@"
}

function WARNING() {
  echo >&2 -e "\e[101m\e[97m[WARNING]\e[0m $@"
}

function ERROR() {
  echo >&2 -e "\e[101m\e[97m[ERROR]\e[0m $@"
}

# render_template [VAR_NAME]... < input.template > output
# Replace each occurrence of '$VAR_NAME' in stdin with value of variable
# VAR_NAME, and print result to stdout.
function render_template {
  local v val escaped_val
  (
    for var_name in "$@"; do
      # ${!var_name} is value of var named by $var_name. If $var_name contains
      # characters that are not alphanumeric or underscore, ${!var_name} fails
      # and we abort. So if ${!var_name} succeeds, $var_name can be part of an
      # awk regex, and requires no escaping.
      val="${!var_name}" || return 1
      # ${val} does require escaping, since it might contain an '&' reference,
      # which is replaced by the string which matched the regex. Numbered
      # references, \1, \2, etc would also be replaced by their matching groups,
      # but since our regex can't contain parentheses, it can't produce capture
      # groups.
      escaped_val=$(sed 's/[&]/\\&/g' <<<"$val")
      # Use environment to set vars instead of -v var=val to prevent awk
      # interpreting any escape sequences in $escaped_val.
      export "__${var_name}__rt=$escaped_val"
      EXPRS+=('gsub("\\$" "'"$var_name"'", ENVIRON["'"__${var_name}__rt"'"]);')
    done
    awk "{ ${EXPRS[*]} print }"
  )
}
