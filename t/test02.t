BEGIN {
    print "1..6\n";
}

use Inline;
Inline->import(C => <DATA>);

print "not " unless (add(3.5, 7.7) == 10);
print "ok 1\n";

print "not " unless (subtract(3.5, 7.7) == -4);
print "ok 2\n";

print_test(3);
print_test(4);
print_test_ref(\5);
print_test_ref(\6);

__END__

int add(int x, int y) {
    return x + y;
}

int subtract(int x, int y) {
    return x - y;
}

int print_test(int test_num) {
    printf("ok %d\n", test_num);
    return 1;
}

int print_test_ref(SV* test_num_ref) {
    int test_num = (int) SvIV(SvRV(test_num_ref));
    printf("ok %d\n", test_num);
    return 1;
}

