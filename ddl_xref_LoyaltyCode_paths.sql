
/****** Object:  Table [dbo].[xref_LoyaltyCode_paths]    Script Date: 4/1/2021 11:13:24 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[xref_LoyaltyCode_paths](
	[Feature_name] [varchar](50) NULL,
	[code type] [varchar](50) NULL,
	[ACT_PATH] [varchar](500) NULL,
	[SiteSpecificCode] [varchar](10) NULL,
	[Comment] [varchar](250) NULL,
) ON [PRIMARY]

GO

CREATE CLUSTERED INDEX [ndx_path] ON [dbo].[xref_LoyaltyCode_paths]
(
	[ACT_PATH] ASC,
	[Feature_name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)

SET ANSI_PADDING OFF
GO


