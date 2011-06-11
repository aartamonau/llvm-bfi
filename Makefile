NAME := bfi
LLFLAGS := -O3

$(NAME): $(NAME).o

%.s: %.ll
	llc $(LLFLAGS) $< -o $@

.PHONY: clean
clean:
	@rm -f $(NAME) *.o *.s
