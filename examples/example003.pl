greet('Ingy');
greet(42);

use Inline C => <<'END_OF_C_CODE';

void greet(SV* sv_name) {
  printf("Hello %s!\n", SvPV(sv_name, PL_na));
}

END_OF_C_CODE
