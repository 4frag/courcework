-- ============================================================================
-- 1. СОЗДАНИЕ СХЕМЫ ТАБЛИЦ (9 сущностей, 30+ атрибутов)
-- ============================================================================

-- Создаем БД, если нет
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'AutoSalon')
BEGIN
    CREATE DATABASE AutoSalon;
END;
GO

USE AutoSalon;
GO

-- Очистка старых объектов, если они есть (для идемпотентности)
DROP TRIGGER IF EXISTS tr_OnDeleteCar;
DROP TRIGGER IF EXISTS tr_OnUpdateCost;
DROP PROCEDURE IF EXISTS sp_ShortFilter;
DROP PROCEDURE IF EXISTS sp_GetClientReport;
DROP PROCEDURE IF EXISTS sp_AddCar;
DROP FUNCTION IF EXISTS fn_GetCarsByYear;
DROP FUNCTION IF EXISTS fn_GetClientTotal;
DROP VIEW IF EXISTS v_ExpensiveCars;
DROP VIEW IF EXISTS v_ClientOrders;
DROP VIEW IF EXISTS v_CarDetails;
DROP TABLE IF EXISTS PriceLog;
DROP TABLE IF EXISTS TestDrives;
DROP TABLE IF EXISTS ServiceHistory;
DROP TABLE IF EXISTS Contracts;
DROP TABLE IF EXISTS Cars;
DROP TABLE IF EXISTS Employees;
DROP TABLE IF EXISTS Clients;
DROP TABLE IF EXISTS Branches;
DROP TABLE IF EXISTS Suppliers;
GO

-- Таблица 1: Поставщики
CREATE TABLE Suppliers (
    SupplierID INT IDENTITY(1,1) PRIMARY KEY,
    SupplierName VARCHAR(100) NOT NULL,
    SupplierCountry VARCHAR(50) NOT NULL
);

-- Таблица 2: Филиалы
CREATE TABLE Branches (
    BranchID INT IDENTITY(1,1) PRIMARY KEY,
    BranchName VARCHAR(100) NOT NULL,
    BranchAddress VARCHAR(255) NOT NULL,
    BranchPhone VARCHAR(20),
    BranchChef VARCHAR(100)
);

-- Таблица 3: Клиенты
CREATE TABLE Clients (
    ClientID INT IDENTITY(1,1) PRIMARY KEY,
    LastName VARCHAR(50) NOT NULL,
    FirstName VARCHAR(50),      -- Дополнительное поле по ТЗ
    MiddleName VARCHAR(50),     -- Дополнительное поле по ТЗ
    ClientPassport VARCHAR(20) NOT NULL,
    ClientPhone VARCHAR(20),
    ClientEmail VARCHAR(100),
    BaseSign BIT NOT NULL,       -- 1 - Юр лицо, 0 - Физ лицо
    BankName VARCHAR(100),
    BankAccount VARCHAR(50)
);

-- Таблица 4: Сотрудники
CREATE TABLE Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    BranchID INT FOREIGN KEY REFERENCES Branches(BranchID),
    EmpLastName VARCHAR(50) NOT NULL,
    EmpFirstName VARCHAR(50) NOT NULL,
    Position VARCHAR(50) NOT NULL,
    ManagerSalary DECIMAL(10,2) NOT NULL CHECK (ManagerSalary > 0) -- Constraint 1
);

-- Таблица 5: Автомобили
CREATE TABLE Cars (
    CarID INT IDENTITY(1,1) PRIMARY KEY,
    SupplierID INT FOREIGN KEY REFERENCES Suppliers(SupplierID),
    Brand VARCHAR(50) NOT NULL,
    Model VARCHAR(50) NOT NULL,
    VIN VARCHAR(17) NOT NULL, -- Будет альтернативным ключом (AK)
    EngineID VARCHAR(30),
    EngineVolume DECIMAL(3,1),
    EnginePower INT,
    BodyType VARCHAR(30),
    Color VARCHAR(30),
    Year INT NOT NULL CHECK (Year >= 2000), -- Constraint 2
    Mileage INT DEFAULT 0,
    Transmission VARCHAR(20),
    DriveType VARCHAR(20),
    Cost DECIMAL(12,2) NOT NULL CHECK (Cost > 0), -- Constraint 3
    IsNew BIT DEFAULT 1
);

-- Таблица 6: Договоры продаж
CREATE TABLE Contracts (
    ContractID INT IDENTITY(1,1) PRIMARY KEY,
    BranchID INT FOREIGN KEY REFERENCES Branches(BranchID),
    CarID INT FOREIGN KEY REFERENCES Cars(CarID),
    ClientID INT FOREIGN KEY REFERENCES Clients(ClientID),
    EmployeeID INT FOREIGN KEY REFERENCES Employees(EmployeeID),
    ContractDate DATETIME NOT NULL,
    TotalPrice DECIMAL(12,2) NOT NULL,
    PaymentMethod VARCHAR(30),
    DiscountRate DECIMAL(5,2) DEFAULT 0.00,
    WarrantyPeriod INT DEFAULT 12
);

-- Таблица 7: История ТО
CREATE TABLE ServiceHistory (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    CarID INT FOREIGN KEY REFERENCES Cars(CarID) ON DELETE CASCADE,
    ServiceDate DATETIME NOT NULL,
    Description VARCHAR(MAX),
    ServiceCost DECIMAL(10,2)
);

-- Таблица 8: Тест-драйвы
CREATE TABLE TestDrives (
    DriveID INT IDENTITY(1,1) PRIMARY KEY,
    CarID INT FOREIGN KEY REFERENCES Cars(CarID),
    ClientID INT FOREIGN KEY REFERENCES Clients(ClientID),
    DriveDate DATETIME NOT NULL,
    Feedback VARCHAR(500)
);

-- Таблица 9: Лог цен (для триггера)
CREATE TABLE PriceLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    CarID INT,
    OldCost DECIMAL(12,2),
    NewCost DECIMAL(12,2),
    ChangeDate DATETIME DEFAULT GETDATE()
);
GO

-- ============================================================================
-- 2. ИНДЕКСЫ И АЛЬТЕРНАТИВНЫЕ КЛЮЧИ (AK, IE по ТЗ)
-- ============================================================================

-- Альтернативный ключ (Unique Constraint) [AK1]
ALTER TABLE Cars ADD CONSTRAINT AK_VIN UNIQUE (VIN);
GO

-- Инверсные ключи (Обычные некластеризованные индексы для поиска) [IE1, IE2, IE3]
CREATE NONCLUSTERED INDEX IE_ContractDate ON Contracts(ContractDate);
CREATE NONCLUSTERED INDEX IE_CarCost ON Cars(Cost);
CREATE NONCLUSTERED INDEX IE_ClientLastName ON Clients(LastName);
GO


-- ============================================================================
-- 3. ПРЕДСТАВЛЕНИЯ (VIEWS)
-- ============================================================================

-- Представление 1: Детали авто и филиала
CREATE VIEW v_CarDetails AS
SELECT c.CarID, c.Brand, c.Model, c.Cost, b.BranchName, b.BranchAddress
FROM Cars c
LEFT JOIN Contracts con ON c.CarID = con.CarID
LEFT JOIN Branches b ON con.BranchID = b.BranchID;
GO

-- Представление 2: Заготовка для уточняющих запросов (Клиенты + Контракты)
CREATE VIEW v_ClientOrders AS
SELECT cl.ClientID, cl.LastName, co.ContractID, co.TotalPrice, co.ContractDate
FROM Clients cl
INNER JOIN Contracts co ON cl.ClientID = co.ClientID;
GO

-- Представление 3: Модифицирующее с WITH CHECK OPTION
CREATE VIEW v_ExpensiveCars AS
SELECT CarID, Brand, Model, Cost, Year, VIN
FROM Cars
WHERE Cost > 50000
WITH CHECK OPTION;
GO


-- ============================================================================
-- 4. ХРАНИМЫЕ ФУНКЦИИ
-- ============================================================================

-- 1. Скалярная функция: сумма покупок клиента
CREATE FUNCTION fn_GetClientTotal (@ClientID INT)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Total DECIMAL(18,2);
    SELECT @Total = SUM(TotalPrice) FROM Contracts WHERE ClientID = @ClientID;
    RETURN ISNULL(@Total, 0);
END;
GO

-- 2. Табличная функция: выборка машин по году
CREATE FUNCTION fn_GetCarsByYear (@TargetYear INT)
RETURNS TABLE
AS
RETURN (
    SELECT CarID, Brand, Model, Cost, Year 
    FROM Cars 
    WHERE Year = @TargetYear
);
GO


-- ============================================================================
-- 5. ХРАНИМЫЕ ПРОЦЕДУРЫ
-- ============================================================================

-- Процедура 1: Добавление машины (с OUTPUT параметром)
CREATE PROCEDURE sp_AddCar
    @Brand VARCHAR(50), @Model VARCHAR(50), @VIN VARCHAR(17), @Year INT, @Cost DECIMAL(12,2),
    @NewCarID INT OUTPUT
AS
BEGIN
    INSERT INTO Cars (Brand, Model, VIN, Year, Cost)
    VALUES (@Brand, @Model, @VIN, @Year, @Cost);
    
    SET @NewCarID = SCOPE_IDENTITY();
END;
GO

-- Процедура 2: Отчет по клиенту (вызывает внутри СКАЛЯРНУЮ функцию)
CREATE PROCEDURE sp_GetClientReport
    @ClientID INT
AS
BEGIN
    SELECT 
        ClientID,
        LastName,
        ClientPhone,
        dbo.fn_GetClientTotal(@ClientID) AS TotalSpent -- вызов функции
    FROM Clients
    WHERE ClientID = @ClientID;
END;
GO

-- Процедура 3: Сложный фильтр для интерфейса
CREATE PROCEDURE sp_ShortFilter
    @Brand VARCHAR(50),
    @MaxCost DECIMAL(12,2)
AS
BEGIN
    SELECT CarID, Brand, Model, Cost, Year 
    FROM Cars
    WHERE Brand LIKE '%' + @Brand + '%' AND Cost <= @MaxCost;
END;
GO


-- ============================================================================
-- 6. ТРИГГЕРЫ
-- ============================================================================

-- Триггер 1: ON DELETE (Очистка связанных логов при удалении машины)
CREATE TRIGGER tr_OnDeleteCar
ON Cars
AFTER DELETE
AS
BEGIN
    -- Используем таблицу deleted
    DELETE FROM TestDrives 
    WHERE CarID IN (SELECT CarID FROM deleted);
END;
GO

-- Триггер 2: ON UPDATE (Логирование изменения цены)
CREATE TRIGGER tr_OnUpdateCost
ON Cars
AFTER UPDATE
AS
BEGIN
    -- Используем inserted и deleted одновременно
    IF UPDATE(Cost)
    BEGIN
        INSERT INTO PriceLog (CarID, OldCost, NewCost)
        SELECT i.CarID, d.Cost, i.Cost
        FROM inserted i
        JOIN deleted d ON i.CarID = d.CarID;
    END
END;
GO


-- ============================================================================
-- 7. ГЕНЕРАЦИЯ ДАННЫХ
-- ============================================================================
-- ============================================================================
-- 1. БАЗОВЫЕ СПРАВОЧНИКИ (Поставщики и Филиалы)
-- ============================================================================

-- ============================================================================
-- 1. BASE DICTIONARIES (Suppliers and Branches)
-- ============================================================================

PRINT 'Generating suppliers (5) and branches (2)...'

INSERT INTO Suppliers (SupplierName, SupplierCountry)
VALUES 
    ('VAG Group', 'Germany'), 
    ('Toyota Motor', 'Japan'), 
    ('Hyundai Kia', 'South Korea'), 
    ('Ford', 'USA'), 
    ('General Motors', 'USA');

INSERT INTO Branches (BranchName, BranchAddress, BranchPhone, BranchChef)
VALUES 
    ('Central', '1 Main Street, NY', '+1-555-010-0001', 'John Doe'),
    ('Northern', '10 North Avenue, NY', '+1-555-010-0002', 'Jane Smith');
GO

-- ============================================================================
-- 2. GENERATING EMPLOYEES (50)
-- ============================================================================
PRINT 'Generating employees (50)...'
BEGIN TRAN;
DECLARE @e INT = 1;
WHILE @e <= 50
BEGIN
    INSERT INTO Employees (BranchID, EmpLastName, EmpFirstName, Position, ManagerSalary)
    VALUES (
        (ABS(CHECKSUM(NEWID())) % 2) + 1, -- BranchID 1 or 2
        'LastName_' + CAST(@e AS VARCHAR),
        'FirstName_' + CAST(@e AS VARCHAR),
        CHOOSE((ABS(CHECKSUM(NEWID())) % 3) + 1, 'Manager', 'Senior Manager', 'Consultant'),
        50000.00 + (ABS(CHECKSUM(NEWID())) % 100000) -- Salary from 50k to 150k
    );
    SET @e = @e + 1;
END;
COMMIT;
GO

-- ============================================================================
-- 3. GENERATING CLIENTS (2500)
-- ============================================================================
PRINT 'Generating clients (2500)...'
BEGIN TRAN;
DECLARE @c INT = 1;
WHILE @c <= 2500
BEGIN
    INSERT INTO Clients (LastName, FirstName, ClientPassport, ClientPhone, BaseSign)
    VALUES (
        'ClientLast_' + CAST(@c AS VARCHAR),
        'ClientFirst_' + CAST(@c AS VARCHAR),
        RIGHT('0000000000' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR), 10), -- 10 random digits
        '+1555' + RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR), 7),
        ABS(CHECKSUM(NEWID())) % 2 -- 0 or 1
    );
    SET @c = @c + 1;
END;
COMMIT;
GO

-- ============================================================================
-- 4. GENERATING CARS (300)
-- ============================================================================
PRINT 'Generating cars (300)...'
BEGIN TRAN;
DECLARE @car INT = 1;
WHILE @car <= 300
BEGIN
    INSERT INTO Cars (SupplierID, Brand, Model, VIN, Year, Mileage, Cost, IsNew)
    VALUES (
        (ABS(CHECKSUM(NEWID())) % 5) + 1, -- SupplierID from 1 to 5
        CHOOSE((ABS(CHECKSUM(NEWID())) % 5) + 1, 'Audi', 'Toyota', 'Hyundai', 'Ford', 'Chevrolet'),
        'Model_' + CAST((ABS(CHECKSUM(NEWID())) % 20) + 1 AS VARCHAR),
        LEFT(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''), 17), -- Exactly 17 chars for AK_VIN
        2000 + (ABS(CHECKSUM(NEWID())) % 25), -- Year from 2000 to 2024
        ABS(CHECKSUM(NEWID())) % 150000, -- Mileage
        10000.00 + (ABS(CHECKSUM(NEWID())) % 90000), -- Cost from 10k to 100k
        ABS(CHECKSUM(NEWID())) % 2 -- 0 or 1
    );
    SET @car = @car + 1;
END;
COMMIT;
GO

-- ============================================================================
-- 5. GENERATING CONTRACTS (2500)
-- ============================================================================
PRINT 'Generating contracts (2500)...'
BEGIN TRAN;
DECLARE @con INT = 1;
WHILE @con <= 2500
BEGIN
    INSERT INTO Contracts (BranchID, CarID, ClientID, EmployeeID, ContractDate, TotalPrice, PaymentMethod)
    VALUES (
        (ABS(CHECKSUM(NEWID())) % 2) + 1,    -- BranchID (1-2)
        (ABS(CHECKSUM(NEWID())) % 300) + 1,  -- CarID (1-300)
        (ABS(CHECKSUM(NEWID())) % 2500) + 1, -- ClientID (1-2500)
        (ABS(CHECKSUM(NEWID())) % 50) + 1,   -- EmployeeID (1-50)
        DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 1095), GETDATE()), -- Random date in the last 3 years
        10000.00 + (ABS(CHECKSUM(NEWID())) % 90000), -- Random total price
        CHOOSE((ABS(CHECKSUM(NEWID())) % 3) + 1, 'Cash', 'Credit', 'Bank Transfer')
    );
    SET @con = @con + 1;
END;
COMMIT;
GO

-- ============================================================================
-- 6. GENERATING SERVICE HISTORY (1500)
-- ============================================================================
PRINT 'Generating service history (1500)...'
BEGIN TRAN;
DECLARE @sh INT = 1;
WHILE @sh <= 1500
BEGIN
    INSERT INTO ServiceHistory (CarID, ServiceDate, Description, ServiceCost)
    VALUES (
        (ABS(CHECKSUM(NEWID())) % 300) + 1, -- CarID
        DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 1095), GETDATE()), -- Random date in the last 3 years
        CHOOSE((ABS(CHECKSUM(NEWID())) % 4) + 1, 'Oil Change', 'Routine Maintenance', 'Engine Diagnostics', 'Suspension Repair'),
        100.00 + (ABS(CHECKSUM(NEWID())) % 2000)
    );
    SET @sh = @sh + 1;
END;
COMMIT;
GO

-- ============================================================================
-- 7. GENERATING TEST DRIVES (1000)
-- ============================================================================
PRINT 'Generating test drives (1000)...'
BEGIN TRAN;
DECLARE @td INT = 1;
WHILE @td <= 1000
BEGIN
    INSERT INTO TestDrives (CarID, ClientID, DriveDate, Feedback)
    VALUES (
        (ABS(CHECKSUM(NEWID())) % 300) + 1, -- CarID
        (ABS(CHECKSUM(NEWID())) % 2500) + 1, -- ClientID
        DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 365), GETDATE()), -- Random date in the last year
        CHOOSE((ABS(CHECKSUM(NEWID())) % 4) + 1, 'Great handling', 'Too expensive', 'Very comfortable', 'Not enough legroom')
    );
    SET @td = @td + 1;
END;
COMMIT;
GO

PRINT 'Data generation completed successfully!';
GO