# Turn the monolithic build-stack recipe into a resumable recipe.  The upstream
# file deliberately has no targets, so top-level source acquisitions are the
# stable boundaries between logical dependency builds.
function step_name(line, fields, name) {
  split(line, fields, /[ 	]+/)
  name = fields[2]
  gsub(/[^[:alnum:]._-]/, "-", name)
  return name
}
function emit_step(    id) {
  if (step == "") return
  sequence++
  id = sprintf("%03d-%s", sequence, step_name(step))
  print "if resume_begin '" id "' \"$(resume_hash <<'RESUME_STEP_DEFINITION'"
  printf "%s", body
  print "RESUME_STEP_DEFINITION"
  print ")\"; then"
  printf "%s", body
  print "  resume_finish '" id "' \"$(resume_hash <<'RESUME_STEP_DEFINITION'"
  printf "%s", body
  print "RESUME_STEP_DEFINITION"
  print ")\""
  print "fi"
  step = ""
  body = ""
}
function is_step(line) {
  return line ~ /^src[ \t]/ || line ~ /^download[ \t]+jack_headers\.tar\.gz[ \t]/ || line ~ /^download[ \t]+ladspa\.h[ \t]/
}
function resume_runtime() {
  print "# Added by ardour-ci: per-dependency checkpoint and snapshot support."
  print ": ${RESUME_DIR:?RESUME_DIR must be set}"
  print ": ${BUILD_STACK_REV:?BUILD_STACK_REV must be set}"
  print "RESUME_HAVE_BASE=0"
  print "resume_hash() { { cat; printf '%s\\n' \"$GLOBAL_CPPFLAGS|$GLOBAL_CFLAGS|$GLOBAL_CXXFLAGS|$GLOBAL_LDFLAGS|$STACKCFLAGS|$CFLAGS\"; } | shasum -a 256 | awk '{print $1}'; }"
  print "resume_copy() { local source=$1 target=$2; rm -rf \"$target\"; mkdir -p \"$(dirname \"$target\")\"; cp -cR \"$source\" \"$target\" 2>/dev/null || { rm -rf \"$target\"; cp -R \"$source\" \"$target\"; }; }"
  print "resume_restore() { local id snapshot; id=$1; snapshot=\"$RESUME_DIR/snapshots/$id\"; rm -rf \"$PREFIX\" \"$BLDDEP\" \"$BUILDD\"; [ ! -d \"$snapshot/inst\" ] || resume_copy \"$snapshot/inst\" \"$PREFIX\"; [ ! -d \"$snapshot/tool\" ] || resume_copy \"$snapshot/tool\" \"$BLDDEP\"; mkdir -p \"$PREFIX\" \"$BLDDEP\" \"$BUILDD\"; }"
  print "resume_invalidate() { local id=$1 state; for state in \"$RESUME_DIR/state\"/*; do [ -e \"$state\" ] || continue; [ \"$(basename \"$state\")\" \\< \"$id\" ] && continue; rm -f \"$state\"; rm -rf \"$RESUME_DIR/snapshots/$(basename \"$state\")\"; done; }"
  print "resume_begin() { local id hash state snapshot; id=$1; hash=$2; state=\"$RESUME_DIR/state/$id\"; snapshot=\"$RESUME_DIR/snapshots/$id\"; mkdir -p \"$RESUME_DIR/state\" \"$RESUME_DIR/snapshots\"; if [ -f \"$state\" ] && [ \"$(cat \"$state\")\" = \"$BUILD_STACK_REV $id $hash\" ] && [ -d \"$snapshot\" ]; then resume_restore \"$id\"; RESUME_HAVE_BASE=1; echo \"*** RESUME: reusing $id\"; return 1; fi; [ ! -f \"$state\" ] || echo \"*** RESUME: invalidating $id (recipe or build flags changed)\"; resume_invalidate \"$id\"; if [ \"$RESUME_HAVE_BASE\" -eq 0 ]; then rm -rf \"$PREFIX\" \"$BLDDEP\" \"$BUILDD\"; mkdir -p \"$PREFIX\" \"$BLDDEP\" \"$BUILDD\"; fi; rm -rf \"$BUILDD\"; mkdir -p \"$BUILDD\"; echo \"*** RESUME: building $id\"; return 0; }"
  print "resume_finish() { local id hash snapshot temporary; id=$1; hash=$2; snapshot=\"$RESUME_DIR/snapshots/$id\"; temporary=\"$snapshot.tmp.$$\"; rm -rf \"$temporary\"; mkdir -p \"$temporary\"; [ ! -d \"$PREFIX\" ] || resume_copy \"$PREFIX\" \"$temporary/inst\"; [ ! -d \"$BLDDEP\" ] || resume_copy \"$BLDDEP\" \"$temporary/tool\"; rm -rf \"$snapshot\"; mv \"$temporary\" \"$snapshot\"; printf '%s %s %s\\n' \"$BUILD_STACK_REV\" \"$id\" \"$hash\" > \"$RESUME_DIR/state/$id\"; RESUME_HAVE_BASE=1; }"
  print "mkdir -p \"$RESUME_DIR\" \"$PREFIX\" \"$BUILDD\" \"$BLDDEP\""
}
BEGIN { reset = 0; in_steps = 0; step = ""; body = "" }
{
  if (!reset && $0 == "rm -rf ${PREFIX}") { reset = 1; next }
  if (reset) {
    if ($0 == "mkdir -p ${BLDDEP}") { reset = 0; resume_runtime(); next }
    next
  }
  if (is_step($0)) {
    if (!in_steps) in_steps = 1
    else emit_step()
    step = $0
  }
  if (in_steps) body = body $0 "\n"
  else print
}
END { if (reset) { print "error: unsupported x-applearm.sh reset block" > "/dev/stderr"; exit 2 }; emit_step() }
