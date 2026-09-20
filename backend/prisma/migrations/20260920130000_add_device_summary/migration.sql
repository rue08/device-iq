-- CreateTable
CREATE TABLE "DeviceSummary" (
    "deviceId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "score" INTEGER,
    "basedOnSnapshotAt" TIMESTAMP(3) NOT NULL,
    "modelId" TEXT NOT NULL,
    "generatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DeviceSummary_pkey" PRIMARY KEY ("deviceId")
);

-- AddForeignKey
ALTER TABLE "DeviceSummary" ADD CONSTRAINT "DeviceSummary_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
