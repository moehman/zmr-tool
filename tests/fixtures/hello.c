#include <stdio.h>
#include <string.h>

int g = 0;

void foo() {
  printf("hello!\n");
}

void bar(int i) {
  while (i--) {
    printf("world\n");
  }
}

void baz() {
  if (g) {
    printf("!\n");
  } else {
    printf("?\n");
  }
} /* comment */

int main(int argc, char *argv[])
{
  foo();
  bar(5);
  baz();

  if (argc > 1) {
    if (strcmp(argv[1], "help") == 0) {
      printf("help requested!\n");
    }
  } /* if */
  return 0;
}
