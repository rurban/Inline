greet(qw(Brian Ingerson Ingy Me Myself I));

use Inline C => <<'END_OF_C_CODE';

void greet(SV* name1, ...) {
  Inline_Stack_Vars;
  int i;

  for (i = 0; i < Inline_Stack_Items; i++) 
    printf("Hello %s!\n", SvPV(Inline_Stack_Item(i), PL_na));

  Inline_Stack_Void;
}

END_OF_C_CODE
