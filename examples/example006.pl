print greet('Ingy', 42);

use Inline C => <<'END_OF_C_CODE';

void greet(char* name, int number) {
  dXSARGS;
  int i;

  sp = mark;

  for (i = 0; i < number; i++)
    XPUSHs(sv_2mortal(newSVpvf("Hello %s!\n", name))); 

  PUTBACK;
}

END_OF_C_CODE

__END__
