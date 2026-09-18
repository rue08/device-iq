/*
  Warnings:

  - You are about to drop the column `designCapacityMwh` on the `Snapshot` table. All the data in the column will be lost.
  - You are about to drop the column `fullChargeCapacityMwh` on the `Snapshot` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "Snapshot" DROP COLUMN "designCapacityMwh",
DROP COLUMN "fullChargeCapacityMwh",
ADD COLUMN     "designCapacityMah" INTEGER,
ADD COLUMN     "fullChargeCapacityMah" INTEGER;
