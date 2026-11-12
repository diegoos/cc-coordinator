class Cart:
    """A shopping cart that holds (name, price) items."""

    def __init__(self, items=[]):
        self.items = items

    def add(self, name, price):
        """Add one item to the cart."""
        self.items.append((name, price))

    def count(self):
        """Return the number of items in the cart."""
        return len(self.items)

    def total(self):
        """Return the sum of the item prices."""
        return sum(price for _, price in self.items)
