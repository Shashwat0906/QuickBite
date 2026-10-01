'use strict';
/**
 * Seeds a realistic catalogue: 7 cafes around central Delhi, ~60 dishes with
 * customizations, coupons, and a demo account for interviews.
 *
 *   npm run db:seed            # only seeds an empty database
 *   SEED_FORCE=true npm run db:seed   # wipes catalogue + orders first (dev only!)
 *
 * Images are Unsplash photos (free to use under the Unsplash License).
 */
require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();
const img = (id) => `https://images.unsplash.com/${id}?w=800&q=80&auto=format&fit=crop`;

const I = {
  coffee: 'photo-1509042239860-f550ce710b93',
  coffeeCup: 'photo-1495474472287-4d71bcdd2085',
  cafeInterior: 'photo-1554118811-1e0d58224f24',
  cafeCounter: 'photo-1501339847302-ac426a4a7cbb',
  beans: 'photo-1442512595331-e89e73853f31',
  latte: 'photo-1461023058943-07fcbe16d735',
  cappuccino: 'photo-1517701604599-bb29b565090c',
  latteArt: 'photo-1541167760496-1628856ab772',
  cappuccino2: 'photo-1572442388796-11668a67e53d',
  icedCoffee: 'photo-1517487881594-2787fef5ebf7',
  coldBrew: 'photo-1559496417-e7f25cb247f3',
  pizza: 'photo-1513104890138-7c749659a591',
  pizza2: 'photo-1565299624946-b28f40a0ae38',
  burger: 'photo-1568901346375-23c9450c58cd',
  burger2: 'photo-1550547660-d9450f859349',
  bowl: 'photo-1546069901-ba9599a7e63c',
  salad: 'photo-1512621776951-a57141f2eefd',
  sandwich: 'photo-1528735602780-2552fd46c7af',
  frenchToast: 'photo-1484723091739-30a097e8f929',
  pancakes: 'photo-1567620905732-2d1ec7ab7445',
  donut: 'photo-1551024601-bec78aea704b',
  cake: 'photo-1578985545062-69928b1d9587',
  iceCream: 'photo-1563805042-7684c019e1cb',
  iceCream2: 'photo-1497034825429-c343d7c6a68f',
  pasta: 'photo-1621996346565-e3dbc646d9a9',
  pasta2: 'photo-1473093295043-cdd812d0e601',
  croissant: 'photo-1555507036-ab1f4038808a',
  bread: 'photo-1509440159596-0249088772ff',
  brownie: 'photo-1606313564200-e75d5e30476c',
  curry: 'photo-1585937421612-70a008356fbe',
  samosa: 'photo-1601050690597-df0568f70950',
  eggs: 'photo-1525351484163-7529414344d8',
  friedRice: 'photo-1512058564366-18510be2db19',
  tea: 'photo-1556679343-c7306c1976bc',
  cookies: 'photo-1558961363-fa8fdf82db35',
  smoothie: 'photo-1505253716362-afaea1d3d1af',
  juice: 'photo-1600271886742-f049cd451bba',
};

// ---- Reusable customization templates (prices in paise) -------------------
const COFFEE = [
  { name: 'Size', minSelect: 1, maxSelect: 1, options: [['Regular', 0], ['Large', 4000]] },
  { name: 'Milk', minSelect: 0, maxSelect: 1, options: [['Oat milk', 5000], ['Almond milk', 5000], ['Lactose-free', 3000]] },
  { name: 'Extras', minSelect: 0, maxSelect: 2, options: [['Extra shot', 4000], ['Vanilla syrup', 3000], ['Hazelnut syrup', 3000]] },
];
const COLD = [
  { name: 'Size', minSelect: 1, maxSelect: 1, options: [['Regular', 0], ['Large', 5000]] },
  { name: 'Sweetness', minSelect: 0, maxSelect: 1, options: [['Less sweet', 0], ['No sugar', 0]] },
];
const PIZZA = [
  { name: 'Size', minSelect: 1, maxSelect: 1, options: [['Medium 9"', 0], ['Large 12"', 15000]] },
  { name: 'Crust', minSelect: 1, maxSelect: 1, options: [['Classic hand-tossed', 0], ['Thin crust', 0], ['Cheese burst', 9000]] },
  { name: 'Extra toppings', minSelect: 0, maxSelect: 3, options: [['Jalapeños', 4000], ['Olives', 4000], ['Extra cheese', 6000], ['Mushrooms', 4000]] },
];
const BURGER = [
  { name: 'Add-ons', minSelect: 0, maxSelect: 3, options: [['Cheese slice', 3000], ['Peri-peri fries', 7000], ['Extra patty', 9000]] },
];
const BOWL = [
  { name: 'Base', minSelect: 1, maxSelect: 1, options: [['Brown rice', 0], ['Quinoa', 4000], ['Greens only', 0]] },
  { name: 'Protein', minSelect: 0, maxSelect: 1, options: [['Paneer', 6000], ['Tofu', 6000], ['Grilled chicken', 8000]] },
];
const DESSERT = [{ name: 'Add', minSelect: 0, maxSelect: 1, options: [['Scoop of vanilla ice cream', 6000]] }];
const CHAI = [{ name: 'Size', minSelect: 1, maxSelect: 1, options: [['Cutting', 0], ['Full', 2000], ['Kettle (serves 4)', 12000]] }];

// [name, description, pricePaise, image, diet, customizations, flags]
const CAFES = [
  {
    name: 'Brew & Bloom', slug: 'brew-and-bloom', featured: true, lat: 28.6328, lng: 77.2197,
    address: 'N-Block, Connaught Place, New Delhi', phone: '+911140001111', prep: 7, fee: 2500, min: 14900, rating: 4.6, ratingCount: 1240,
    description: 'Specialty coffee, all-day breakfast and fresh bakes in the heart of CP.', cuisines: ['coffee', 'breakfast', 'bakery'],
    image: I.cafeInterior, banner: I.latteArt, hours: ['06:00', '03:00'],
    menu: {
      Coffee: [
        ['Signature Cappuccino', 'Double-shot espresso, velvety microfoam, a dusting of cocoa.', 18900, I.cappuccino2, 'VEG', COFFEE, { best: true, pop: 940 }],
        ['Flat White', 'Ristretto shots with silky steamed milk. Strong and smooth.', 19900, I.latteArt, 'VEG', COFFEE, { pop: 610 }],
        ['Caramel Latte', 'Espresso, steamed milk and house-made salted caramel.', 21900, I.latte, 'VEG', COFFEE, { pop: 520 }],
        ['Americano', 'Espresso lengthened with hot water. Clean and bold.', 14900, I.coffeeCup, 'VEG', COFFEE, { pop: 300 }],
      ],
      'Cold Beverages': [
        ['Cold Brew Tonic', '18-hour cold brew over tonic and orange peel.', 22900, I.coldBrew, 'VEG', COLD, { best: true, pop: 700 }],
        ['Iced Mocha', 'Espresso, dark chocolate and cold milk over ice.', 23900, I.icedCoffee, 'VEG', COLD, { pop: 410 }],
      ],
      Breakfast: [
        ['Brioche French Toast', 'Thick brioche, berry compote, maple and whipped mascarpone.', 32900, I.frenchToast, 'EGG', [], { best: true, pop: 580 }],
        ['Buttermilk Pancakes', 'Stack of three with maple syrup and butter.', 29900, I.pancakes, 'EGG', [], { pop: 450 }],
        ['Eggs Benedict', 'Poached eggs, hollandaise and spinach on toasted muffin.', 34900, I.eggs, 'EGG', [], { pop: 330 }],
      ],
      Bakery: [
        ['Butter Croissant', 'Flaky, laminated with French butter. Baked every morning.', 14900, I.croissant, 'VEG', [], { pop: 800, stock: 25 }],
        ['Sourdough Toast & Butter', 'House sourdough, cultured butter, sea salt.', 15900, I.bread, 'VEG', [], { pop: 200 }],
      ],
    },
  },
  {
    name: 'Ember Roastery', slug: 'ember-roastery', featured: true, lat: 28.6003, lng: 77.2270,
    address: 'Middle Lane, Khan Market, New Delhi', phone: '+911140002222', prep: 6, fee: 2000, min: 12900, rating: 4.7, ratingCount: 860,
    description: 'Single-origin Indian coffees roasted in-house, with light bites.', cuisines: ['coffee', 'sandwiches', 'desserts'],
    image: I.cafeCounter, banner: I.beans, hours: ['07:00', '02:00'],
    menu: {
      Coffee: [
        ['Chikmagalur Pour Over', 'Hand-brewed single origin with notes of jaggery and citrus.', 24900, I.coffee, 'VEG', [], { best: true, pop: 400 }],
        ['Hazelnut Latte', 'Espresso, steamed milk, toasted hazelnut syrup.', 20900, I.latte, 'VEG', COFFEE, { pop: 380 }],
        ['Cortado', 'Equal parts espresso and warm milk.', 16900, I.cappuccino2, 'VEG', COFFEE, { pop: 220 }],
      ],
      'Cold Beverages': [
        ['Vietnamese Iced Coffee', 'Strong drip coffee with condensed milk over ice.', 21900, I.icedCoffee, 'VEG', COLD, { best: true, pop: 520 }],
      ],
      Sandwiches: [
        ['Pesto Paneer Sandwich', 'Grilled paneer, basil pesto, sun-dried tomato on sourdough.', 28900, I.sandwich, 'VEG', [], { best: true, pop: 470 }],
        ['Chicken Tikka Panini', 'Smoky tikka, mint mayo and onions, pressed till crisp.', 31900, I.sandwich, 'NON_VEG', [], { pop: 390 }],
      ],
      Desserts: [
        ['Walnut Brownie', 'Fudgy dark-chocolate brownie with toasted walnuts.', 16900, I.brownie, 'EGG', DESSERT, { pop: 610 }],
        ['Choco-chip Cookies (3)', 'Brown-butter cookies, crisp edges, gooey centre.', 14900, I.cookies, 'EGG', [], { pop: 300 }],
      ],
    },
  },
  {
    name: 'Slice Society', slug: 'slice-society', featured: true, lat: 28.5535, lng: 77.1945,
    address: 'Hauz Khas Village, New Delhi', phone: '+911140003333', prep: 12, fee: 3000, min: 19900, rating: 4.4, ratingCount: 2100,
    description: 'Wood-fired sourdough pizzas and fresh pasta.', cuisines: ['pizza', 'pasta', 'italian'],
    image: I.pizza2, banner: I.pizza, hours: ['11:00', '03:00'],
    menu: {
      Pizza: [
        ['Margherita', 'San Marzano tomato, fior di latte, basil, olive oil.', 34900, I.pizza, 'VEG', PIZZA, { best: true, pop: 1200 }],
        ['Farmhouse', 'Peppers, onion, mushroom, sweet corn, mozzarella.', 39900, I.pizza2, 'VEG', PIZZA, { pop: 700 }],
        ['Pepperoni', 'Spicy chicken pepperoni, mozzarella, chilli honey.', 44900, I.pizza2, 'NON_VEG', PIZZA, { best: true, pop: 900 }],
      ],
      Pasta: [
        ['Penne Arrabbiata', 'Fiery tomato, garlic and chilli. Simple and perfect.', 29900, I.pasta2, 'VEG', [], { pop: 500 }],
        ['Spaghetti Aglio e Olio', 'Garlic, chilli flakes, parsley, parmesan.', 28900, I.pasta, 'VEG', [], { pop: 350 }],
        ['Creamy Chicken Alfredo', 'Fettuccine, parmesan cream, grilled chicken.', 36900, I.pasta, 'NON_VEG', [], { pop: 420 }],
      ],
      Desserts: [
        ['Tiramisu', 'Espresso-soaked ladyfingers and mascarpone cream.', 24900, I.cake, 'EGG', [], { pop: 330, stock: 12 }],
      ],
    },
  },
  {
    name: 'The Green Bowl', slug: 'the-green-bowl', featured: false, lat: 28.5918, lng: 77.2273,
    address: 'Meherchand Market, Lodhi Colony, New Delhi', phone: '+911140004444', prep: 8, fee: 2500, min: 14900, rating: 4.5, ratingCount: 640,
    description: 'Wholesome bowls, salads and cold-pressed juices.', cuisines: ['healthy', 'salads', 'juices'],
    image: I.bowl, banner: I.salad, hours: ['08:00', '23:00'],
    menu: {
      'Bowls & Salads': [
        ['Buddha Bowl', 'Roasted veg, hummus, chickpeas, greens, tahini.', 32900, I.bowl, 'VEG', BOWL, { best: true, pop: 520 }],
        ['Mediterranean Salad', 'Feta, olives, cucumber, cherry tomato, lemon-oregano.', 29900, I.salad, 'VEG', BOWL, { pop: 300 }],
        ['Teriyaki Chicken Bowl', 'Glazed chicken, sesame veg, sticky rice.', 37900, I.friedRice, 'NON_VEG', [], { pop: 410 }],
      ],
      'Cold Beverages': [
        ['Berry Blast Smoothie', 'Strawberry, blueberry, banana and Greek yoghurt.', 21900, I.smoothie, 'VEG', COLD, { pop: 360 }],
        ['Cold-pressed Orange', 'Just oranges. Nothing else.', 17900, I.juice, 'VEG', [], { pop: 280 }],
      ],
    },
  },
  {
    name: 'Chai Chowk', slug: 'chai-chowk', featured: true, lat: 28.6519, lng: 77.1909,
    address: 'Ajmal Khan Road, Karol Bagh, New Delhi', phone: '+911140005555', prep: 5, fee: 1500, min: 9900, rating: 4.3, ratingCount: 3100,
    description: 'Kadak chai, hot samosas and desi comfort food.', cuisines: ['tea', 'indian', 'snacks'],
    image: I.tea, banner: I.samosa, hours: ['00:00', '23:59'],
    menu: {
      Tea: [
        ['Masala Chai', 'Assam tea brewed with ginger, cardamom and whole spices.', 6900, I.tea, 'VEG', CHAI, { best: true, pop: 1500 }],
        ['Adrak Elaichi Chai', 'Extra ginger, extra cardamom, extra comfort.', 7900, I.tea, 'VEG', CHAI, { pop: 600 }],
      ],
      'Indian Snacks': [
        ['Punjabi Samosa (2)', 'Spiced potato and peas, mint and tamarind chutney.', 8900, I.samosa, 'VEG', [], { best: true, pop: 1300 }],
        ['Paneer Butter Masala Bowl', 'Rich makhani gravy, paneer, jeera rice.', 27900, I.curry, 'VEG', [], { pop: 520 }],
        ['Butter Chicken Bowl', 'Classic Delhi butter chicken with jeera rice.', 31900, I.curry, 'NON_VEG', [], { pop: 700 }],
      ],
    },
  },
  {
    name: 'Bun Intended', slug: 'bun-intended', featured: false, lat: 28.6415, lng: 77.1209,
    address: 'J-Block Market, Rajouri Garden, New Delhi', phone: '+911140006666', prep: 10, fee: 3000, min: 19900, rating: 4.2, ratingCount: 980,
    description: 'Smash burgers, loaded fries and thick shakes.', cuisines: ['burgers', 'fast food'],
    image: I.burger2, banner: I.burger, hours: ['12:00', '03:00'],
    menu: {
      Burgers: [
        ['Classic Smash Burger', 'Double smashed chicken patty, cheddar, pickles, house sauce.', 27900, I.burger, 'NON_VEG', BURGER, { best: true, pop: 880 }],
        ['Crispy Paneer Burger', 'Crumbed paneer, tandoori mayo, slaw.', 23900, I.burger2, 'VEG', BURGER, { pop: 500 }],
        ['Aloo Tikki Royale', 'Spiced potato patty, mint mayo, onions.', 16900, I.burger2, 'VEG', BURGER, { pop: 640 }],
      ],
      Desserts: [
        ['Glazed Donut', 'Classic yeast-raised donut with vanilla glaze.', 9900, I.donut, 'EGG', [], { pop: 300 }],
        ['Oreo Thick Shake', 'Vanilla ice cream, Oreo crumble, whipped cream.', 19900, I.iceCream2, 'VEG', COLD, { pop: 450 }],
      ],
    },
  },
  {
    name: 'Sugar Rush Patisserie', slug: 'sugar-rush', featured: false, lat: 28.5743, lng: 77.2320,
    address: 'Defence Colony Market, New Delhi', phone: '+911140007777', prep: 6, fee: 2500, min: 14900, rating: 4.8, ratingCount: 410,
    description: 'Celebration cakes, gelato and French pastries.', cuisines: ['desserts', 'bakery'],
    image: I.cake, banner: I.iceCream, hours: ['10:00', '23:00'],
    menu: {
      Desserts: [
        ['Belgian Chocolate Cake Slice', 'Three layers of dark chocolate sponge and ganache.', 21900, I.cake, 'EGG', DESSERT, { best: true, pop: 520 }],
        ['Gelato Duo', 'Two scoops: pick your favourites at the counter.', 19900, I.iceCream, 'VEG', [], { pop: 420 }],
        ['Fudge Brownie Sundae', 'Warm brownie, vanilla gelato, hot fudge.', 24900, I.brownie, 'EGG', [], { pop: 380 }],
      ],
      Bakery: [
        ['Almond Croissant', 'Twice-baked with frangipane and toasted almonds.', 17900, I.croissant, 'EGG', [], { pop: 300, stock: 0 }],
        ['Cookie Box (6)', 'Assorted cookies baked fresh every afternoon.', 29900, I.cookies, 'EGG', [], { pop: 260 }],
      ],
    },
  },
];

const COUPONS = [
  { code: 'WELCOME50', description: '50% off up to ₹100 on your first order', type: 'PERCENT', value: 50, maxDiscountPaise: 10000, minOrderPaise: 19900, usageLimitPerUser: 1 },
  { code: 'QUICK75', description: 'Flat ₹75 off on orders above ₹349', type: 'FLAT', value: 7500, minOrderPaise: 34900, usageLimitPerUser: 5 },
  { code: 'FEAST100', description: 'Flat ₹100 off on orders above ₹599', type: 'FLAT', value: 10000, minOrderPaise: 59900, usageLimitPerUser: 10 },
  { code: 'MONSOON20', description: '20% off — expired offer (for testing)', type: 'PERCENT', value: 20, maxDiscountPaise: 8000, minOrderPaise: 0, usageLimitPerUser: 3, validUntil: new Date('2025-09-30') },
];

async function main() {
  const existing = await prisma.cafe.count();
  if (existing > 0 && process.env.SEED_FORCE !== 'true') {
    console.log(`Database already has ${existing} cafes — skipping seed (set SEED_FORCE=true to wipe and reseed).`);
    return;
  }
  if (process.env.SEED_FORCE === 'true') {
    if (process.env.NODE_ENV === 'production' && process.env.ALLOW_PROD_RESEED !== 'true') throw new Error('Refusing to wipe a production database');
    console.log('Wiping orders and catalogue…');
    await prisma.$transaction([
      prisma.review.deleteMany(), prisma.payment.deleteMany(), prisma.orderStatusEvent.deleteMany(), prisma.orderItem.deleteMany(),
      prisma.order.deleteMany(), prisma.cartItem.deleteMany(), prisma.cart.deleteMany(), prisma.coupon.deleteMany(), prisma.cafe.deleteMany(),
    ]);
  }

  for (const c of CAFES) {
    const cafe = await prisma.cafe.create({
      data: {
        name: c.name, slug: c.slug, description: c.description, imageUrl: img(c.image), bannerUrl: img(c.banner), cuisines: c.cuisines,
        rating: c.rating, ratingCount: c.ratingCount, avgPrepMinutes: c.prep, deliveryFeePaise: c.fee, minOrderPaise: c.min,
        latitude: c.lat, longitude: c.lng, addressLine: c.address, phone: c.phone, isFeatured: c.featured, opensAt: c.hours[0], closesAt: c.hours[1],
      },
    });
    let sort = 0;
    for (const [categoryName, items] of Object.entries(c.menu)) {
      const category = await prisma.menuCategory.create({ data: { cafeId: cafe.id, name: categoryName, sortOrder: sort++ } });
      for (const [name, description, price, image, diet, groups, flags = {}] of items) {
        await prisma.menuItem.create({
          data: {
            cafeId: cafe.id, categoryId: category.id, name, description, pricePaise: price, imageUrl: img(image), diet,
            isBestseller: Boolean(flags.best), popularity: flags.pop || 0, stock: flags.stock ?? null,
            customizations: {
              create: groups.map((g, gi) => ({
                name: g.name, minSelect: g.minSelect, maxSelect: g.maxSelect, sortOrder: gi,
                options: { create: g.options.map(([optName, extra]) => ({ name: optName, extraPricePaise: extra })) },
              })),
            },
          },
        });
      }
    }
    console.log(`  ✓ ${c.name}`);
  }

  for (const coupon of COUPONS) await prisma.coupon.upsert({ where: { code: coupon.code }, create: coupon, update: coupon });

  // Demo accounts (documented in the README — change or remove for a real launch).
  const demo = await prisma.user.upsert({
    where: { email: 'demo@quickbite.app' },
    create: { name: 'Demo User', email: 'demo@quickbite.app', phone: '+919800000000', passwordHash: await bcrypt.hash('Demo@1234', 10) },
    update: {},
  });
  if ((await prisma.address.count({ where: { userId: demo.id } })) === 0) {
    await prisma.address.create({ data: { userId: demo.id, label: 'Home', line1: 'B-12, Barakhamba Road', city: 'New Delhi', pincode: '110001', latitude: 28.6290, longitude: 77.2250, isDefault: true } });
    await prisma.address.create({ data: { userId: demo.id, label: 'Work', line1: '3rd Floor, Statesman House', line2: 'Connaught Place', city: 'New Delhi', pincode: '110001', latitude: 28.6280, longitude: 77.2230 } });
  }
  await prisma.user.upsert({
    where: { email: 'staff@quickbite.app' },
    create: { name: 'Cafe Staff', email: 'staff@quickbite.app', role: 'CAFE_STAFF', passwordHash: await bcrypt.hash('Staff@1234', 10) },
    update: {},
  });

  const items = await prisma.menuItem.count();
  console.log(`Seeded ${CAFES.length} cafes, ${items} menu items, ${COUPONS.length} coupons. Demo login: demo@quickbite.app / Demo@1234`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
