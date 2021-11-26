/* Playground to play with numbers:

     Example:
      X: 200
      Y: 1
      split: -100

      x: 50
      y: 0.5

      new
      X: 150
      Y: 1.5
      split: -75

      x: 30
      y: 0.5

      new:
      X: 120
      Y: 2
      split: -60

      x: 60
      y: 0.5

      new:
      X: 180
      Y: 1.5
      split: -80

      //add x / sub y
      y=Yx/(X+2x)
      x=Xy/(Y-2y)

      //add y / sub x
      x=Xy/(Y+2y)
      y=Yx/(X-2x)
    */

function addXsubYForY(X, Y, x) {
    //y=Yx/(X+2x)
    return Y * x / (X + (2 * x));
}

function addXsubYForX(X, Y, y) {
    //x=Xy/(Y-2y)
    return X * y / (Y - (2 * y));
}

function addYsubXForX(X, Y, y) {
    // x=Xy/(Y+2y)
    return X * y / (Y + (2 * y));
}

function addYsubXForY(X, Y, x) {
    // y=Yx/(X-2x)
    return Y * x / (X - (2 * x));
}

let X = 200;
let Y = 1;
let x = 50;
console.log("Ini P: " + X + " for " + Y + " price: " + (X / Y));
let y = addYsubXForY(X, Y, x);
X -= x;
Y += y;
console.log("trade: " + x + " for " + y + " price: " + (x / y));
console.log("New P: " + X + " for " + Y + " price: " + (X / Y));

x = 60;
y = addYsubXForY(X, Y, x);
X -= x;
Y += y;
console.log("trade: " + x + " for " + y + " price: " + (x / y));
console.log("New P: " + X + " for " + Y + " price: " + (X / Y));

y = 2;
x = addXsubYForX(X, Y, y);
X += x;
Y -= y;
console.log("trade: " + x + " for " + y + " price: " + (x / y));
console.log("New P: " + X + " for " + Y + " price: " + (X / Y));


X = 200;
Y = 1;
console.log("Ini P: " + X + " for " + Y + " price: " + (X / Y));

y = 0.3;
x = addXsubYForX(X, Y, y);
X += x;
Y -= y;
console.log("trade: " + x + " for " + y + " price: " + (x / y));
console.log("New P: " + X + " for " + Y + " price: " + (X / Y));

x = 150;
y = addYsubXForY(X, Y, x);
X -= x;
Y += y;
console.log("trade: " + x + " for " + y + " price: " + (x / y));
console.log("New P: " + X + " for " + Y + " price: " + (X / Y));

y = 1;
x = addXsubYForX(X, Y, y);
X += x;
Y -= y;
console.log("trade: " + x + " for " + y + " price: " + (x / y));
console.log("New P: " + X + " for " + Y + " price: " + (X / Y));




