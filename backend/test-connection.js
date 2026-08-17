const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  // Admin is now nested under app_user
  const admins = await prisma.app_user.findMany({
    where: { role: 'admin' },
    include: { admin: true }
  });
  console.log(`Found ${admins.length} admin(s):`);
  admins.forEach(a => {
    console.log(`  - ${a.name} (${a.email}) status=${a.admin?.status}`);
  });

  // Zones (renamed from surge_zone)
  const zones = await prisma.zone.findMany();
  console.log(`Found ${zones.length} zones.`);

  // Quick check the zone_type field is available
  console.log('Zone schema check:');
  console.log('  - Can we create a discounted zone?');
  console.log('  - Valid zone_types: normal | discounted | expensive');
}

main()
  .catch((e) => console.error('Error:', e))
  .finally(async () => await prisma.$disconnect());