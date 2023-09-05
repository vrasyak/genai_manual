create or alter procedure [fact].[sp_CustomerRevenue](
 @CustomerID int = null, @FromYear int = null, @ToYear int = null, @Period varchar(8) = null
)
as
begin
	--create an ErrorLog table if does not exist
	if not exists (select 1 from sys.objects where object_id = OBJECT_ID(N'[fact].[ErrorLog]') and type in (N'U') and schema_id = schema_id (N'fact'))
		begin
			declare @ErrorTableCreate as nvarchar(max)
			set @ErrorTableCreate = 'create table [fact].[ErrorLog] ([ErrorID] [int] identity (1,1), [ErrorNumber] [int], [ErrorSeverity] [int], [ErrorMessage] varchar(255), [Custumerid] [int], [Period] [varchar](8), [CreatedAt] [datetime])'
			exec (@ErrorTableCreate)
		end

	declare @ErrorNumber [int],
		@ErrorSeverity [int],
		@ErrorMessage [varchar](255)

	begin try
		declare @DefaultFromYear [int],
			@DefaultToYear [int],
			@DefaultPeriod [varchar](8) = 'Y'

		select @DefaultFromYear = min(year([Invoice Date Key])), @DefaultToYear = max(year([Invoice Date Key])) from [WideWorldImportersDW-Standard].[Fact].[Sale]

		declare @TableName varchar (max)

		declare @CustomerName varchar(50)

		if object_id('TempDB..#TempData') is not null
			drop table #TempData;

		create table #TempData(
			[CustomerId] [int],
			[CustomerName] [varchar](50),
			[Period] [varchar](8),
			[Revenue] [numeric](19,2),)

		if exists (select 1 from [WideWorldImportersDW-Standard].[Dimension].[Customer] where [Customer Key] = @CustomerID)
			begin
				select @CustomerName = left([Customer],50) from [WideWorldImportersDW-Standard].[Dimension].[Customer] where [Customer Key] = @CustomerID
			end

		if ((@FromYear is null) or (@FromYear < @DefaultFromYear or @FromYear > @DefaultToYear))
			begin
				select @FromYear = min(year([Invoice Date Key])) from [WideWorldImportersDW-Standard].[Fact].[Sale]
			end

		if ((@ToYear is null) or (@ToYear < @DefaultFromYear or @ToYear > @DefaultToYear))
			begin
				select @ToYear = max(year([Invoice Date Key])) from [WideWorldImportersDW-Standard].[Fact].[Sale]
			end

		--validate the @Period parametr
		if (@Period not in ('Year','Y', 'Month', 'M', 'Quarter', 'Q'))
			begin
				set @DefaultPeriod = 'Y'
			end
		else
			begin 
				set @DefaultPeriod = @Period
			end

		set @TableName = coalesce(cast(@CustomerID as varchar(8)) + '_' + @CustomerName, 'All') + '_' + case when @FromYear = @ToYear then cast(@FromYear as varchar(8)) else cast(@FromYear as varchar(8)) + '_' + cast(@ToYear as varchar(8)) end + coalesce('_' + upper(left(@DefaultPeriod, 1)), 'Y')

		if exists (select 1 from sys.objects where object_id = OBJECT_ID(N'[fact].[' + @TableName + ']') and type in (N'U') and schema_id = schema_id (N'fact'))
			begin
				declare @delete as nvarchar(max) = 'drop table [fact].['+ @TableName + ']'
				exec (@delete)
			end

			begin
				declare @create as nvarchar(max)
				set @create = 'create table fact.['+ @TableName + '] ([CustomerID] [int], [CustomerName] [varchar](50), [Period] [varchar](8), [Revenue] [numeric](19,2) )'
				exec (@create)
			end

		--for the specified customer
		if (coalesce(@CustomerID,-1) >= 0)
			begin
				--monthly based analitics
				if (@DefaultPeriod in ('Month','M'))
					begin
						insert into #TempData([CustomerId], [CustomerName], [Period], [Revenue])
						select c.[Customer Key] as [CustomerID]
							,c.[Customer] as [CustomerName]
							,(convert(varchar(3), datename(month, s.[Invoice Date Key])) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4))) as [Period]
							,isnull(sum(s.[Quantity] * s.[Unit Price]), 0.00) as Revenue
						from [WideWorldImportersDW-Standard].[Dimension].[Customer] as c
							join [WideWorldImportersDW-Standard].[Fact].[Sale] as s
								on c.[Customer Key] = s.[Customer Key]
						where c.[Customer Key] = @CustomerID
							and year(s.[Invoice Date Key]) between @FromYear and @ToYear
						group by c.[Customer Key], c.[Customer], (convert(varchar(3), datename(month, s.[Invoice Date Key])) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4)))
					end

				--default based analitics
				else if (@DefaultPeriod in ('Quarter','Q'))
					begin
						insert into #TempData([CustomerId], [CustomerName], [Period], [Revenue])
						select c.[Customer Key] as [CustomerID]
							,c.[Customer] as [CustomerName]
							,('Q' + cast(datepart(quarter,s.[Invoice Date Key]) as varchar(1)) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4))) as [Period]
							,isnull(sum(s.[Quantity] * s.[Unit Price]), 0.00) as Revenue
						from [WideWorldImportersDW-Standard].[Dimension].[Customer] as c
							join [WideWorldImportersDW-Standard].[Fact].[Sale] as s
								on c.[Customer Key] = s.[Customer Key]
						where c.[Customer Key] = @CustomerID
							and year(s.[Invoice Date Key]) between @FromYear and @ToYear
						group by c.[Customer Key], c.[Customer], ('Q' + cast(datepart(quarter,s.[Invoice Date Key]) as varchar(1)) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4)))
					end

				--add data to the newly created table
				else
					begin
						insert into #TempData([CustomerId], [CustomerName], [Period], [Revenue])
						select c.[Customer Key] as [CustomerID]
							,c.[Customer] as [CustomerName]
							,year(s.[Invoice Date Key]) as [Period]
							,isnull(sum(s.[Quantity] * s.[Unit Price]), 0.00) as Revenue
						from [WideWorldImportersDW-Standard].[Dimension].[Customer] as c
							join [WideWorldImportersDW-Standard].[Fact].[Sale] as s
								on c.[Customer Key] = s.[Customer Key]
						where c.[Customer Key] = @CustomerID
							and year(s.[Invoice Date Key]) between @FromYear and @ToYear
						group by c.[Customer Key], c.[Customer], year(s.[Invoice Date Key])
					end
			end

		--for all customers
		else
			begin
				--monthly based analitics
				if (@DefaultPeriod in ('Month','M'))
					begin
						insert into #TempData([CustomerId], [CustomerName], [Period], [Revenue])
						select c.[Customer Key] as [CustomerID]
							,c.[Customer] as [CustomerName]
							,(convert(varchar(3), datename(month, s.[Invoice Date Key])) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4))) as [Period]
							,isnull(sum(s.[Quantity] * s.[Unit Price]), 0.00) as Revenue
						from [WideWorldImportersDW-Standard].[Dimension].[Customer] as c
							join [WideWorldImportersDW-Standard].[Fact].[Sale] as s
								on c.[Customer Key] = s.[Customer Key]
						where year(s.[Invoice Date Key]) between @FromYear and @ToYear
						group by c.[Customer Key], c.[Customer], (convert(varchar(3), datename(month, s.[Invoice Date Key])) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4)))
					end

				--Quarter based analitics
				else if (@DefaultPeriod in ('Quarter','Q')) --default Year based analitics
					begin
						insert into #TempData([CustomerId], [CustomerName], [Period], [Revenue])
						select c.[Customer Key] as [CustomerID]
							,c.[Customer] as [CustomerName]
							,('Q' + cast(datepart(quarter,s.[Invoice Date Key]) as varchar(1)) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4))) as [Period]
							,isnull(sum(s.[Quantity] * s.[Unit Price]), 0.00) as Revenue
						from [WideWorldImportersDW-Standard].[Dimension].[Customer] as c
							join [WideWorldImportersDW-Standard].[Fact].[Sale] as s
								on c.[Customer Key] = s.[Customer Key]
						where year(s.[Invoice Date Key]) between @FromYear and @ToYear
						group by c.[Customer Key], c.[Customer], ('Q' + cast(datepart(quarter,s.[Invoice Date Key]) as varchar(1)) + ' ' + cast(year(s.[Invoice Date Key]) as varchar(4)))
					end

				--deafult Year based analitics
				else
					begin
						insert into #TempData([CustomerId], [CustomerName], [Period], [Revenue])
						select c.[Customer Key] as [CustomerID]
							,c.[Customer] as [CustomerName]
							,year(s.[Invoice Date Key]) as [Period]
							,isnull(sum(s.[Quantity] * s.[Unit Price]), 0.00) as Revenue
						from [WideWorldImportersDW-Standard].[Dimension].[Customer] as c
							join [WideWorldImportersDW-Standard].[Fact].[Sale] as s
								on c.[Customer Key] = s.[Customer Key]
						where year(s.[Invoice Date Key]) between @FromYear and @ToYear
						group by c.[Customer Key], c.[Customer], year(s.[Invoice Date Key])
					end
			end

		--add data to the newly created table
		if exists (select 1 from #TempData)
			begin
				declare @InsertSctipt nvarchar(max)
				set @InsertSctipt = 
				'insert into [fact].[' + @TableName + '] ([CustomerID], [CustomerName], [Period], [Revenue])
				select [CustomerID], [CustomerName], [Period], [Revenue]
				from #TempData'
				exec (@InsertSctipt)
			end

		if object_id('TempDB..#TempData') is not null
			drop table #TempData;
	end try
	begin catch

		set @ErrorNumber =  error_number()
		set	@ErrorSeverity = error_severity()
		set @ErrorMessage = 'Message: ' + isnull(cast(error_message() as varchar (1000)),'') + ' ' +
							 'Object: ' + isnull(cast(error_procedure() as varchar (1000)),'') + ' ' +
							 'Line: ' + isnull(cast(error_line() as varchar(10)),'')

		insert into [fact].[ErrorLog] ([ErrorNumber], [Errorseverity], [ErrorMessage], [Custumerid], [Period], [CreatedAt])
		values (@ErrorNumber, @ErrorSeverity, @ErrorMessage, @CustomerID, @Period, getdate())
	
	end catch
end
go