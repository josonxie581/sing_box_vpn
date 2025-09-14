package main

/*
#include <stdio.h>
static void hello() { printf("hello from C\\n"); }
*/
import "C"

func main() {
	C.hello()
}
