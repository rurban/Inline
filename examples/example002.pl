# NOTE: This example may segfault. At the very least it will produce something
# unexpected. This is the intention. "example003.pl" fixes the problem.
#
greet('Ingy');
greet(42);

use Inline C => <<'END_OF_C_CODE';

void greet(SV* sv_name) {
  printf("Hello %s!\n", SvPVX(sv_name));
}

END_OF_C_CODE
