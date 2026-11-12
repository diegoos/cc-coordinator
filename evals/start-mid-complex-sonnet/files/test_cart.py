import unittest

from cart import Cart


class CartTest(unittest.TestCase):
    def test_add_one_item(self):
        cart = Cart()
        cart.add("book", 12)
        self.assertEqual(cart.count(), 1)
        self.assertEqual(cart.total(), 12)

    def test_add_two_items(self):
        cart = Cart()
        cart.add("pen", 3)
        cart.add("mug", 7)
        self.assertEqual(cart.count(), 2)
        self.assertEqual(cart.total(), 10)

    def test_start_with_items(self):
        cart = Cart([("lamp", 20)])
        cart.add("bulb", 5)
        self.assertEqual(cart.count(), 2)
        self.assertEqual(cart.total(), 25)


if __name__ == "__main__":
    unittest.main()
