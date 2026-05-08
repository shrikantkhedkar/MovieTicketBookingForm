/**
 * BookingControllerTest
 * --------------------------------------------------
 * Comprehensive test class — 90%+ coverage.
 * ✅ Booked_Seat__c kadhla — formula field ahe, write hot nahi
 */
@isTest
private class BookingControllerTest {
    
    // ============================================
    // TEST DATA SETUP
    // ============================================
    @testSetup
    static void setupTestData() {
        Theatre__c theatre = new Theatre__c(
            Name = 'Test PVR',
            Theatre_Capacity__c = 100
        );
        insert theatre;
        
        // ✅ Booked_Seat__c SET KARAT NAHI — formula field ahe
        Movie__c movie = new Movie__c(
            Name = 'Test Movie',
            Theatre__c = theatre.Id,
            Duration__c = 2.30
        );
        insert movie;
    }
    
    
    // ============================================
    // POSITIVE TESTS
    // ============================================
    
    @isTest
    static void testGetTheatres() {
        Test.startTest();
        List<Theatre__c> theatres = BookingController.getTheatres();
        Test.stopTest();
        
        System.assertEquals(1, theatres.size(), 'Ek theatre asla pahije');
        System.assertEquals('Test PVR', theatres[0].Name);
    }
    
    @isTest
    static void testGetMoviesByTheatre() {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        
        Test.startTest();
        List<Movie__c> movies = BookingController.getMoviesByTheatre(t.Id);
        Test.stopTest();
        
        System.assertEquals(1, movies.size(), 'Ek movie asla pahije');
    }
    
    @isTest
    static void testGetMoviesByTheatreBlank() {
        Test.startTest();
        List<Movie__c> movies = BookingController.getMoviesByTheatre(null);
        Test.stopTest();
        
        System.assertEquals(0, movies.size(), 'Empty list asla pahije');
    }
    
    @isTest
    static void testGetMovieDetails() {
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        
        Test.startTest();
        Movie__c result = BookingController.getMovieDetails(m.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals('Test Movie', result.Name);
    }
    
    @isTest
    static void testGetMovieDetailsBlank() {
        Test.startTest();
        Movie__c result = BookingController.getMovieDetails(null);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }
    
    @isTest
    static void testCreateBookingSuccess() {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        
        Test.startTest();
        String bookingId = BookingController.createBooking(data);
        Test.stopTest();
        
        System.assertNotEquals(null, bookingId, 'Booking ID return zala pahije');
        
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Email = 'test@example.com'];
        System.assertEquals(1, contacts.size(), 'Contact create zala pahije');
        
        List<Booking__c> bookings = [SELECT Id, Ticket_Price__c FROM Booking__c];
        System.assertEquals(1, bookings.size(), 'Booking create zala pahije');
        System.assertEquals(250, bookings[0].Ticket_Price__c, 
            'Booking var Ticket_Price__c save zala pahije');
    }
    
    @isTest
    static void testCreateBookingExistingContact() {
        Contact existing = new Contact(
            FirstName = 'Old',
            LastName = 'Name',
            Email = 'test@example.com',
            Phone = '1111111111'
        );
        insert existing;
        
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        
        Test.startTest();
        BookingController.createBooking(data);
        Test.stopTest();
        
        Contact updated = [SELECT FirstName FROM Contact WHERE Email = 'test@example.com'];
        System.assertEquals('Shrikant', updated.FirstName, 
            'Existing contact update zala pahije');
        
        Integer count = [SELECT COUNT() FROM Contact WHERE Email = 'test@example.com'];
        System.assertEquals(1, count, 'Duplicate contact nako');
    }
    
    
    // ============================================
    // BULK TEST
    // ============================================
    @isTest
    static void testBulkBookings() {
        Theatre__c bigTheatre = new Theatre__c(
            Name = 'Big Theatre',
            Theatre_Capacity__c = 500
        );
        insert bigTheatre;
        
        // ✅ Booked_Seat__c SET KARAT NAHI — formula field ahe
        Movie__c bigMovie = new Movie__c(
            Name = 'Bulk Movie',
            Theatre__c = bigTheatre.Id,
            Duration__c = 2.30
        );
        insert bigMovie;
        
        List<BookingController.BookingWrapper> wrappers = 
            new List<BookingController.BookingWrapper>();
        
        for (Integer i = 0; i < 50; i++) {
            BookingController.BookingWrapper data = buildValidBooking(
                bigTheatre.Id, bigMovie.Id
            );
            data.email = 'bulk' + i + '@example.com';
            data.numberOfSeats = 2;
            wrappers.add(data);
        }
        
        Test.startTest();
        List<String> ids = BookingService.saveBookingsBulk(wrappers);
        Test.stopTest();
        
        System.assertEquals(50, ids.size(), '50 bookings save zali pahijet');
        
        Integer bookingCount = [SELECT COUNT() FROM Booking__c];
        System.assertEquals(50, bookingCount);
        
        Integer contactCount = [SELECT COUNT() FROM Contact WHERE Email LIKE 'bulk%'];
        System.assertEquals(50, contactCount);
    }
    
    
    // ============================================
    // SLOT-WISE BOOKING TEST
    // ============================================
    @isTest
    static void testSlotWiseBooking_DifferentShowTimes() {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        Date today = Date.today();
        
        BookingController.BookingWrapper booking6PM = buildValidBooking(t.Id, m.Id);
        booking6PM.showTime = '6:00 PM';
        booking6PM.bookingDate = today;
        booking6PM.numberOfSeats = 2;
        booking6PM.email = 'user6pm@example.com';
        
        BookingController.BookingWrapper booking9PM = buildValidBooking(t.Id, m.Id);
        booking9PM.showTime = '9:00 PM';
        booking9PM.bookingDate = today;
        booking9PM.numberOfSeats = 3;
        booking9PM.email = 'user9pm@example.com';
        
        Test.startTest();
        String id6PM = BookingController.createBooking(booking6PM);
        String id9PM = BookingController.createBooking(booking9PM);
        Test.stopTest();
        
        System.assertNotEquals(null, id6PM, '6PM booking success vhayli pahije');
        System.assertNotEquals(null, id9PM, '9PM booking success vhayli pahije');
    }
    
    
    // ============================================
    // getSeatsBySlot TEST
    // ============================================
    @isTest
    static void testGetSeatsBySlot() {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        Date today = Date.today();
        
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        data.showTime = '6:00 PM';
        data.bookingDate = today;
        data.numberOfSeats = 5;
        BookingController.createBooking(data);
        
        Test.startTest();
        BookingController.SlotSeatInfo info6PM = BookingController.getSeatsBySlot(
            m.Id, t.Id, '6:00 PM', today
        );
        BookingController.SlotSeatInfo info9PM = BookingController.getSeatsBySlot(
            m.Id, t.Id, '9:00 PM', today
        );
        Test.stopTest();
        
        System.assertEquals(5, info6PM.bookedSeats, '6PM la 5 booked');
        System.assertEquals(95, info6PM.availableSeats, '6PM la 95 available');
        System.assertEquals(0, info9PM.bookedSeats, '9PM la 0 booked');
        System.assertEquals(100, info9PM.availableSeats, '9PM la 100 available');
    }
    
    
    // ============================================
    // NEGATIVE TESTS
    // ============================================
    
    @isTest
    static void testValidation_BlankFirstName() {
        runValidationTest('firstName', '');
    }
    
    @isTest
    static void testValidation_BlankLastName() {
        runValidationTest('lastName', '');
    }
    
    @isTest
    static void testValidation_BlankEmail() {
        runValidationTest('email', '');
    }
    
    @isTest
    static void testValidation_InvalidEmail() {
        runValidationTest('email', 'invalid-email');
    }
    
    @isTest
    static void testValidation_BlankPhone() {
        runValidationTest('phone', '');
    }
    
    @isTest
    static void testValidation_InvalidPhone() {
        runValidationTest('phone', '123');
    }
    
    @isTest
    static void testValidation_BlankTheatre() {
        runValidationTest('theatreId', '');
    }
    
    @isTest
    static void testValidation_BlankShowTime() {
        runValidationTest('showTime', '');
    }
    
    @isTest
    static void testValidation_BlankTicketType() {
        runValidationTest('ticketType', '');
    }
    
    @isTest
    static void testValidation_ZeroSeats() {
        runValidationTest('numberOfSeats', 0);
    }
    
    @isTest
    static void testValidation_TooManySeats() {
        runValidationTest('numberOfSeats', 15);
    }
    
    @isTest
    static void testValidation_BlankPayment() {
        runValidationTest('paymentMode', '');
    }
    
    
    // ============================================
    // INSUFFICIENT SEATS TEST
    // ============================================
    @isTest
    static void testInsufficientSeats() {
        Theatre__c smallTheatre = new Theatre__c(
            Name = 'Small',
            Theatre_Capacity__c = 5
        );
        insert smallTheatre;
        
        // ✅ Booked_Seat__c SET KARAT NAHI — formula field ahe
        Movie__c smallMovie = new Movie__c(
            Name = 'Small Movie',
            Theatre__c = smallTheatre.Id,
            Duration__c = 2.30
        );
        insert smallMovie;
        
        BookingController.BookingWrapper first = buildValidBooking(
            smallTheatre.Id, smallMovie.Id
        );
        first.numberOfSeats = 4;
        first.email = 'first@example.com';
        BookingController.createBooking(first);
        
        BookingController.BookingWrapper second = buildValidBooking(
            smallTheatre.Id, smallMovie.Id
        );
        second.numberOfSeats = 3;
        second.email = 'second@example.com';
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BookingController.createBooking(second);
        } catch (Exception e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('available'), 
                'Insufficient seats message yaychi: ' + e.getMessage()
            );
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            'Insufficient seats exception aali pahije');
    }
    
    
    // ============================================
    // NULL DATA TEST
    // ============================================
    @isTest
    static void testNullData() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BookingController.createBooking(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            'Null data var exception yayla pahije');
    }
    
    
    // ============================================
    // HELPER METHODS
    // ============================================
    
    private static BookingController.BookingWrapper buildValidBooking(
        Id theatreId, Id movieId
    ) {
        BookingController.BookingWrapper data = new BookingController.BookingWrapper();
        data.firstName = 'Shrikant';
        data.lastName = 'Khedkar';
        data.email = 'test@example.com';
        data.phone = '9876543210';
        data.theatreId = theatreId;
        data.movieId = movieId;
        data.showTime = '6:00 PM';
        data.ticketType = 'Gold';
        data.ticketPrice = 250;
        data.numberOfSeats = 2;
        data.paymentMode = 'UPI';
        data.totalAmount = 500;
        data.bookingDate = Date.today();
        return data;
    }
    
    private static void runValidationTest(String fieldName, Object invalidValue) {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        
        if (fieldName == 'firstName') data.firstName = (String) invalidValue;
        else if (fieldName == 'lastName') data.lastName = (String) invalidValue;
        else if (fieldName == 'email') data.email = (String) invalidValue;
        else if (fieldName == 'phone') data.phone = (String) invalidValue;
        else if (fieldName == 'theatreId') data.theatreId = (String) invalidValue;
        else if (fieldName == 'showTime') data.showTime = (String) invalidValue;
        else if (fieldName == 'ticketType') data.ticketType = (String) invalidValue;
        else if (fieldName == 'paymentMode') data.paymentMode = (String) invalidValue;
        else if (fieldName == 'numberOfSeats') data.numberOfSeats = (Integer) invalidValue;
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BookingController.createBooking(data);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            fieldName + ' validation fail honari');
    }
}